USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.SchemaMigrations WHERE Numero = 31
    )
        THROW 70040, 'Primero ejecute la migracion 031.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 32
    )
    BEGIN
        IF OBJECT_ID(N'dbo.SP_Pedidos_ConfirmarCheckout', N'P') IS NULL
            THROW 70041, 'No existe el SP de checkout.', 1;

        -- ALTER PROCEDURE se ejecuta en un batch dinamico.
        EXEC sys.sp_executesql N'ALTER PROCEDURE [dbo].[SP_Pedidos_ConfirmarCheckout]
    @IDUsuario INT,
    @IDReserva BIGINT,
    @IDDireccion INT,
    @ClaveIdempotencia VARCHAR(100),
    @TotalEsperado DECIMAL(19,2),
    @CodigoCupon VARCHAR(50) = NULL
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

    -- Normalizar el codigo antes de incluirlo en la identidad de la solicitud.
    -- NULL conserva exactamente el hash original (checkout-v1), para que
    -- sigan funcionando los reintentos de compras anteriores a la migracion.
    IF @CodigoCupon IS NOT NULL
    BEGIN
        SET @CodigoCupon = UPPER(LTRIM(RTRIM(@CodigoCupon)));

        IF LEN(@CodigoCupon) < 3
           OR @CodigoCupon COLLATE Latin1_General_100_BIN2
              LIKE ''%[^A-Z0-9_-]%''
            THROW 66029, ''Codigo de cupon invalido.'', 1;
    END;

    DECLARE @Hash BINARY(32);

    IF @CodigoCupon IS NULL
        SET @Hash = HASHBYTES(
            ''SHA2_256'',
            CONCAT(
                N''checkout-v1|'', @IDUsuario, N''|'',
                @IDReserva, N''|'', @IDDireccion, N''|'',
                CONVERT(NVARCHAR(40), @TotalEsperado)
            )
        );
    ELSE
        SET @Hash = HASHBYTES(
            ''SHA2_256'',
            CONCAT(
                N''checkout-v2|'', @IDUsuario, N''|'',
                @IDReserva, N''|'', @IDDireccion, N''|'',
                CONVERT(NVARCHAR(40), @TotalEsperado), N''|'',
                @CodigoCupon
            )
        );

    DECLARE @PedidoExistente BIGINT;
    DECLARE @HashExistente BINARY(32);
    DECLARE @IDCarrito BIGINT;
    DECLARE @EstadoReserva VARCHAR(12);
    DECLARE @ExpiraEn DATETIME2(3);
    DECLARE @Pedido BIGINT;
    DECLARE @Subtotal DECIMAL(19,2);
    DECLARE @Descuento DECIMAL(19,2) = 0;
    DECLARE @TotalCobrar DECIMAL(19,2);
    DECLARE @IDCupon INT;
    DECLARE @TipoDescuento VARCHAR(15);
    DECLARE @ValorCupon DECIMAL(19,2);
    DECLARE @MontoMinimo DECIMAL(19,2);
    DECLARE @LimiteUsos INT;
    DECLARE @UsosRealizados INT;
    DECLARE @LimitePorCliente INT;
    DECLARE @FechaInicio DATETIME2(3);
    DECLARE @FechaFin DATETIME2(3);
    DECLARE @ActivoCupon BIT;
    DECLARE @UsosCliente BIGINT;
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
        -- 5.1 VALIDAR Y BLOQUEAR CUPON
        -- ==========================================
        -- CONTRATO: @TotalEsperado sigue siendo el SUBTOTAL sin descuento.
        -- El precio final se calcula exclusivamente en SQL Server.
        IF @CodigoCupon IS NOT NULL
        BEGIN
            -- La fila del cupon queda bloqueada hasta COMMIT/ROLLBACK.
            -- Esto serializa los checkouts que compiten por el ultimo uso.
            SELECT
                @IDCupon = c.IDCupon,
                @TipoDescuento = c.TipoDescuento,
                @ValorCupon = c.Valor,
                @MontoMinimo = c.MontoMinimo,
                @LimiteUsos = c.LimiteUsos,
                @UsosRealizados = c.UsosRealizados,
                @LimitePorCliente = c.LimitePorCliente,
                @FechaInicio = c.FechaInicio,
                @FechaFin = c.FechaFin,
                @ActivoCupon = c.Activo
            FROM dbo.Cupones AS c WITH (UPDLOCK, HOLDLOCK)
            WHERE c.Codigo = @CodigoCupon;

            IF @IDCupon IS NULL OR @ActivoCupon = 0
                THROW 66030, ''Cupon inexistente o inactivo.'', 1;

            SET @Fecha = SYSUTCDATETIME();

            IF @Fecha < @FechaInicio OR @Fecha >= @FechaFin
                THROW 66031, ''Cupon fuera de vigencia.'', 1;

            IF @Subtotal < @MontoMinimo
                THROW 66032, ''Subtotal menor al minimo del cupon.'', 1;

            IF @UsosRealizados >= @LimiteUsos
                THROW 66033, ''Cupon sin usos disponibles.'', 1;

            -- Con el cupon bloqueado, ninguna compra concurrente puede
            -- confirmar un nuevo uso de este cupon antes de nosotros.
            SELECT @UsosCliente = COUNT_BIG(*)
            FROM dbo.UsosCupon WITH (HOLDLOCK)
            WHERE IDCupon = @IDCupon AND IDUsuario = @IDUsuario;

            IF @UsosCliente >= @LimitePorCliente
                THROW 66034, ''Limite por cliente alcanzado.'', 1;

            IF @Subtotal <= 0
                THROW 66035, ''El subtotal no permite aplicar descuento.'', 1;

            IF @TipoDescuento = ''PORCENTAJE''
                SET @Descuento = CONVERT(
                    DECIMAL(19,2),
                    ROUND(@Subtotal * @ValorCupon / 100.00, 2)
                );
            ELSE IF @TipoDescuento = ''MONTO_FIJO''
                SET @Descuento = @ValorCupon;
            ELSE
                THROW 66036, ''Tipo de cupon no soportado.'', 1;

            -- Un descuento nunca puede superar el precio de la compra.
            IF @Descuento > @Subtotal
                SET @Descuento = @Subtotal;

            IF @Descuento <= 0
                THROW 66035, ''El cupon no genera un descuento aplicable.'', 1;
        END;

        SET @TotalCobrar = @Subtotal - @Descuento;

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
            @Descuento,
            @TotalCobrar,
            @CodigoCupon,
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
        -- 8.1 CONSUMIR CUPON EN LA MISMA TRANSACCION
        -- ==========================================
        IF @IDCupon IS NOT NULL
        BEGIN
            UPDATE dbo.Cupones
            SET UsosRealizados = UsosRealizados + 1
            WHERE IDCupon = @IDCupon
              AND Activo = 1
              AND UsosRealizados < LimiteUsos
              AND FechaInicio <= SYSUTCDATETIME()
              AND FechaFin > SYSUTCDATETIME();

            IF @@ROWCOUNT <> 1
                THROW 66033, ''Cupon agotado o ya no vigente.'', 1;

            INSERT INTO dbo.UsosCupon (
                IDCupon,
                IDPedido,
                IDUsuario,
                MontoDescuento,
                FechaUso
            )
            VALUES (
                @IDCupon,
                @Pedido,
                @IDUsuario,
                @Descuento,
                SYSUTCDATETIME()
            );
        END;

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
            @TotalCobrar,
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
END;';

        GRANT EXECUTE ON OBJECT::dbo.SP_Pedidos_ConfirmarCheckout
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (Numero, Nombre)
        VALUES (32, N'032_CheckoutCouponsProcedure');

        PRINT 'Migracion 032 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM sys.parameters
            WHERE object_id = OBJECT_ID(N'dbo.SP_Pedidos_ConfirmarCheckout')
              AND name = N'@CodigoCupon'
        )
            THROW 70042,
                'Migracion 032 registrada pero falta @CodigoCupon.', 1;

        PRINT 'Migracion 032 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
