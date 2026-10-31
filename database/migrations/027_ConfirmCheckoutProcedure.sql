USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 26
    )
        THROW 66001,
            'Primero ejecute la migracion 026.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 27
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Pedidos_ConfirmarCheckout',
            N'P'
        ) IS NOT NULL
            THROW 66002,
                'El procedimiento ya existe sin migracion registrada.',
                1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Pedidos_ConfirmarCheckout
    @IDUsuario INT,
    @IDReserva BIGINT,
    @IDDireccion INT,
    @ClaveIdempotencia VARCHAR(100),
    @TotalEsperado DECIMAL(19,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IDUsuario IS NULL OR @IDUsuario <= 0
        THROW 66010, ''Usuario invalido.'', 1;

    IF @IDReserva IS NULL OR @IDReserva <= 0
        THROW 66011, ''Reserva invalida.'', 1;

    IF @IDDireccion IS NULL OR @IDDireccion <= 0
        THROW 66012, ''Direccion invalida.'', 1;

    IF @ClaveIdempotencia IS NULL
       OR DATALENGTH(@ClaveIdempotencia) < 16
       OR DATALENGTH(@ClaveIdempotencia) > 100
        THROW 66013,
            ''Clave de idempotencia invalida.'', 1;

    IF @TotalEsperado IS NULL OR @TotalEsperado < 0
        THROW 66014,
            ''Total esperado invalido.'', 1;

    DECLARE @Hash BINARY(32) = HASHBYTES(
        ''SHA2_256'',
        CONCAT(
            N''checkout-v1|'', @IDUsuario, N''|'',
            @IDReserva, N''|'', @IDDireccion, N''|'',
            CONVERT(NVARCHAR(40), @TotalEsperado)
        )
    );

    DECLARE @PedidoExistente BIGINT;
    DECLARE @HashExistente BINARY(32);
    DECLARE @IDCarrito BIGINT;
    DECLARE @EstadoReserva VARCHAR(12);
    DECLARE @ExpiraEn DATETIME2(3);
    DECLARE @Pedido BIGINT;
    DECLARE @Subtotal DECIMAL(19,2);
    DECLARE @Fecha DATETIME2(3);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Revalidar la cuenta del cliente.
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios AS u
            INNER JOIN dbo.Roles AS ro
                ON ro.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuario
              AND u.Activo = 1
              AND ro.Nombre = ''Cliente''
        )
            THROW 66016,
                ''Cliente no autorizado.'', 1;

        -- ==========================================
        -- 1. VALIDAR IDEMPOTENCIA
        -- ==========================================

        SELECT
            @PedidoExistente = IDPedido,
            @HashExistente = HashSolicitud
        FROM dbo.Pedidos WITH (UPDLOCK, HOLDLOCK)
        WHERE IDUsuario = @IDUsuario
          AND ClaveIdempotencia = @ClaveIdempotencia;

        IF @PedidoExistente IS NOT NULL
        BEGIN
            IF @HashExistente <> @Hash
                THROW 66015,
                    ''La clave de idempotencia se utilizo con otros datos.'',
                    1;

            COMMIT TRANSACTION;

            SELECT
                p.IDPedido,
                p.IDCarrito,
                p.IDReserva,
                p.Estado,
                p.Subtotal,
                p.Descuento,
                p.Total,
                CAST(1 AS BIT) AS Reutilizado
            FROM dbo.Pedidos AS p
            WHERE p.IDPedido = @PedidoExistente;

            RETURN;
        END;

        -- ==========================================
        -- 2. OBTENER CARRITO DE LA RESERVA
        -- ==========================================

        SELECT @IDCarrito = r.IDCarrito
        FROM dbo.ReservasInventario AS r
        WHERE r.IDReserva = @IDReserva
          AND r.IDUsuario = @IDUsuario;

        IF @IDCarrito IS NULL
            THROW 66017,
                ''Reserva no encontrada.'', 1;

        -- Bloquear el carrito.
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Carritos
                WITH (UPDLOCK, HOLDLOCK)
            WHERE IDCarrito = @IDCarrito
              AND IDUsuario = @IDUsuario
              AND Estado = ''ACTIVO''
        )
            THROW 66018,
                ''Carrito no disponible.'', 1;

        CREATE TABLE #Carrito (
            IDVariante INT NOT NULL PRIMARY KEY,
            Cantidad INT NOT NULL
        );

        INSERT INTO #Carrito (
            IDVariante,
            Cantidad
        )
        SELECT
            IDVariante,
            Cantidad
        FROM dbo.DetallesCarrito
            WITH (UPDLOCK, HOLDLOCK)
        WHERE IDCarrito = @IDCarrito;

        IF NOT EXISTS (
            SELECT 1 FROM #Carrito
        )
            THROW 66019,
                ''Carrito vacio.'', 1;

        -- ==========================================
        -- 3. VALIDAR RESERVA VIGENTE
        -- ==========================================

        SELECT
            @EstadoReserva = r.Estado,
            @ExpiraEn = r.ExpiraEn
        FROM dbo.ReservasInventario AS r
            WITH (UPDLOCK, HOLDLOCK)
        WHERE r.IDReserva = @IDReserva
          AND r.IDUsuario = @IDUsuario
          AND r.IDCarrito = @IDCarrito;

        IF @EstadoReserva IS NULL
           OR @EstadoReserva <> ''ACTIVA''
           OR @ExpiraEn <= SYSUTCDATETIME()
            THROW 66020,
                ''Reserva no vigente.'', 1;

        -- Verificar que el carrito no haya cambiado.
        IF EXISTS (
            SELECT 1
            FROM #Carrito AS c
            FULL OUTER JOIN (
                SELECT
                    IDVariante,
                    Cantidad
                FROM dbo.DetallesReserva
                WHERE IDReserva = @IDReserva
            ) AS d
                ON d.IDVariante = c.IDVariante
            WHERE c.IDVariante IS NULL
               OR d.IDVariante IS NULL
               OR c.Cantidad <> d.Cantidad
        )
            THROW 66021,
                ''El carrito cambio despues de reservar.'',
                1;

        -- ==========================================
        -- 4. VALIDAR DIRECCION DE ENTREGA
        -- ==========================================

        DECLARE @Destinatario NVARCHAR(150);
        DECLARE @Telefono NVARCHAR(25);
        DECLARE @Departamento NVARCHAR(100);
        DECLARE @Municipio NVARCHAR(100);
        DECLARE @DireccionLinea1 NVARCHAR(250);
        DECLARE @Referencia NVARCHAR(250);

        SELECT
            @Destinatario = d.Destinatario,
            @Telefono = d.Telefono,
            @Departamento = d.Departamento,
            @Municipio = d.Municipio,
            @DireccionLinea1 = d.DireccionLinea1,
            @Referencia = d.Referencia
        FROM dbo.Direcciones AS d WITH (HOLDLOCK)
        WHERE d.IDDireccion = @IDDireccion
          AND d.IDUsuario = @IDUsuario
          AND d.Activa = 1;

        IF @Destinatario IS NULL
            THROW 66022,
                ''Direccion no disponible para este cliente.'',
                1;

        -- ==========================================
        -- 5. CONGELAR PRECIOS DEL PEDIDO
        -- ==========================================

        CREATE TABLE #Lineas (
            IDVariante INT NOT NULL PRIMARY KEY,
            IDCategoria INT NOT NULL,
            SKU NVARCHAR(64) NOT NULL,
            NombreProducto NVARCHAR(200) NOT NULL,
            PrecioUnitario DECIMAL(19,2) NOT NULL,
            Cantidad INT NOT NULL,
            ImporteLinea DECIMAL(19,2) NOT NULL
        );

        INSERT INTO #Lineas (
            IDVariante,
            IDCategoria,
            SKU,
            NombreProducto,
            PrecioUnitario,
            Cantidad,
            ImporteLinea
        )
        SELECT
            v.IDVariante,
            p.IDCategoria,
            v.SKU,
            p.Nombre,
            v.PrecioActual,
            dr.Cantidad,
            CONVERT(
                DECIMAL(19,2),
                v.PrecioActual * dr.Cantidad
            )
        FROM dbo.DetallesReserva AS dr
        INNER JOIN dbo.Variantes AS v
            WITH (HOLDLOCK)
            ON v.IDVariante = dr.IDVariante
        INNER JOIN dbo.Productos AS p
            WITH (HOLDLOCK)
            ON p.IDProducto = v.IDProducto
        INNER JOIN dbo.Categorias AS ca
            WITH (HOLDLOCK)
            ON ca.IDCategoria = p.IDCategoria
        WHERE dr.IDReserva = @IDReserva
          AND v.Activa = 1
          AND p.Activo = 1
          AND ca.Activa = 1;

        IF (
            SELECT COUNT(*)
            FROM #Lineas
        ) <> (
            SELECT COUNT(*)
            FROM dbo.DetallesReserva
            WHERE IDReserva = @IDReserva
        )
            THROW 66023,
                ''Hay productos no disponibles.'', 1;

        SELECT @Subtotal = SUM(ImporteLinea)
        FROM #Lineas;

        IF @Subtotal IS NULL
           OR @Subtotal <> @TotalEsperado
            THROW 66024,
                ''El total del carrito cambio; debe confirmarse nuevamente.'',
                1;

        -- ==========================================
        -- 6. DESCONTAR INVENTARIO Y GENERAR KARDEX
        -- ==========================================

        DECLARE @Variante INT;
        DECLARE @Cantidad INT;
        DECLARE @Fisica INT;
        DECLARE @ReservasAjenas BIGINT;
        DECLARE @Ultima INT = 0;

        SET @Fecha = SYSUTCDATETIME();

        -- Bloquear las variantes en orden ascendente.
        WHILE EXISTS (
            SELECT 1
            FROM #Lineas
            WHERE IDVariante > @Ultima
        )
        BEGIN
            SELECT TOP (1)
                @Variante = IDVariante,
                @Cantidad = Cantidad
            FROM #Lineas
            WHERE IDVariante > @Ultima
            ORDER BY IDVariante;

            SET @Fisica = NULL;

            SELECT @Fisica = CantidadFisica
            FROM dbo.Existencias
                WITH (UPDLOCK, HOLDLOCK)
            WHERE IDVariante = @Variante;

            IF @Fisica IS NULL
               OR @Fisica < @Cantidad
                THROW 66025,
                    ''Existencia fisica insuficiente.'', 1;

            -- Proteger las reservas de otros clientes.
            SELECT @ReservasAjenas = ISNULL(
                SUM(CONVERT(BIGINT, dr.Cantidad)),
                0
            )
            FROM dbo.DetallesReserva AS dr
            INNER JOIN dbo.ReservasInventario AS r
                ON r.IDReserva = dr.IDReserva
            WHERE dr.IDVariante = @Variante
              AND r.IDReserva <> @IDReserva
              AND r.Estado = ''ACTIVA''
              AND r.ExpiraEn > SYSUTCDATETIME();

            IF CONVERT(BIGINT, @Fisica)
               - @Cantidad < @ReservasAjenas
                THROW 66026,
                    ''La compra comprometeria reservas de otros clientes.'',
                    1;

            UPDATE dbo.Existencias
            SET
                CantidadFisica = @Fisica - @Cantidad,
                FechaActualizacion = @Fecha
            WHERE IDVariante = @Variante;

            INSERT INTO dbo.MovimientosInventario (
                IDVariante,
                IDUsuario,
                TipoMovimiento,
                CantidadFirmada,
                SaldoAnterior,
                SaldoPosterior,
                Motivo,
                FechaMovimiento
            )
            VALUES (
                @Variante,
                @IDUsuario,
                ''SALIDA_VENTA'',
                -@Cantidad,
                @Fisica,
                @Fisica - @Cantidad,
                N''Compra confirmada por checkout'',
                @Fecha
            );

            SET @Ultima = @Variante;
        END;

        -- ==========================================
        -- 7. REGISTRAR PEDIDO
        -- ==========================================

        INSERT INTO dbo.Pedidos (
            IDUsuario,
            IDCarrito,
            IDReserva,
            IDDireccion,
            ClaveIdempotencia,
            HashSolicitud,
            Estado,
            Subtotal,
            Descuento,
            Total,
            CodigoCupon,
            EntregaDestinatario,
            EntregaTelefono,
            EntregaDepartamento,
            EntregaMunicipio,
            EntregaDireccionLinea1,
            EntregaReferencia,
            FechaCreacion,
            FechaActualizacion
        )
        VALUES (
            @IDUsuario,
            @IDCarrito,
            @IDReserva,
            @IDDireccion,
            @ClaveIdempotencia,
            @Hash,
            ''PAGADO'',
            @Subtotal,
            0,
            @Subtotal,
            NULL,
            @Destinatario,
            @Telefono,
            @Departamento,
            @Municipio,
            @DireccionLinea1,
            @Referencia,
            @Fecha,
            @Fecha
        );

        SET @Pedido = CONVERT(
            BIGINT,
            SCOPE_IDENTITY()
        );

        -- ==========================================
        -- 8. REGISTRAR DETALLES
        -- ==========================================

        INSERT INTO dbo.DetallesPedido (
            IDPedido,
            IDVariante,
            IDCategoria,
            SKU,
            NombreProducto,
            PrecioUnitario,
            Cantidad,
            ImporteLinea
        )
        SELECT
            @Pedido,
            IDVariante,
            IDCategoria,
            SKU,
            NombreProducto,
            PrecioUnitario,
            Cantidad,
            ImporteLinea
        FROM #Lineas;

        -- ==========================================
        -- 9. REGISTRAR PAGO SIMULADO
        -- ==========================================

        INSERT INTO dbo.Pagos (
            IDPedido,
            MetodoPago,
            Estado,
            Monto,
            ReferenciaPago,
            FechaCreacion,
            FechaConfirmacion
        )
        VALUES (
            @Pedido,
            ''SIMULADO'',
            ''APROBADO'',
            @Subtotal,
            CONCAT(N''SIM-'', @Pedido),
            @Fecha,
            @Fecha
        );

        -- ==========================================
        -- 10. HISTORIAL DE ESTADOS
        -- ==========================================

        INSERT INTO dbo.HistorialEstadosPedido (
            IDPedido,
            IDUsuario,
            EstadoAnterior,
            EstadoNuevo,
            Observacion,
            FechaCambio
        )
        VALUES (
            @Pedido,
            @IDUsuario,
            NULL,
            ''PAGADO'',
            N''Pedido creado; pago simulado aprobado'',
            @Fecha
        );

        -- ==========================================
        -- 11. CONFIRMAR RESERVA Y CARRITO
        -- ==========================================

        UPDATE dbo.ReservasInventario
        SET
            Estado = ''CONFIRMADA'',
            FechaCierre = @Fecha
        WHERE IDReserva = @IDReserva
          AND Estado = ''ACTIVA'';

        IF @@ROWCOUNT <> 1
            THROW 66027,
                ''No fue posible confirmar la reserva.'', 1;

        UPDATE dbo.Carritos
        SET
            Estado = ''CONVERTIDO'',
            UltimaActividad = @Fecha
        WHERE IDCarrito = @IDCarrito
          AND Estado = ''ACTIVO'';

        IF @@ROWCOUNT <> 1
            THROW 66028,
                ''No fue posible convertir el carrito.'', 1;

        -- ==========================================
        -- 12. CONFIRMAR TRANSACCION
        -- ==========================================

        COMMIT TRANSACTION;

        SELECT
            p.IDPedido,
            p.IDCarrito,
            p.IDReserva,
            p.Estado,
            p.Subtotal,
            p.Descuento,
            p.Total,
            CAST(0 AS BIT) AS Reutilizado
        FROM dbo.Pedidos AS p
        WHERE p.IDPedido = @Pedido;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        -- Permitir ejecucion desde Express.
        GRANT EXECUTE
        ON OBJECT::dbo.SP_Pedidos_ConfirmarCheckout
        TO [shopcart_api];

        -- Registrar migracion.
        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            27,
            N'027_ConfirmCheckoutProcedure'
        );

        PRINT 'Migracion 027 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Pedidos_ConfirmarCheckout',
            N'P'
        ) IS NULL
            THROW 66003,
                'Migracion 027 registrada pero falta el SP.',
                1;

        PRINT 'Migracion 027 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
