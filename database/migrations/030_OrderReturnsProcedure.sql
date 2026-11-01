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
        WHERE Numero = 29
    )
        THROW 69001,
            'Primero ejecute la migracion 029.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 30
    )
    BEGIN
        IF OBJECT_ID(N'dbo.Devoluciones', N'U') IS NOT NULL
           OR OBJECT_ID(N'dbo.DetallesDevolucion', N'U') IS NOT NULL
           OR OBJECT_ID(N'dbo.SP_Pedidos_RegistrarDevolucion', N'P') IS NOT NULL
            THROW 69002,
                'Existen objetos de devoluciones sin migracion registrada.',
                1;

        -- ==========================================
        -- TABLA DE DEVOLUCIONES
        -- ==========================================

        CREATE TABLE dbo.Devoluciones (
            IDDevolucion BIGINT IDENTITY(1,1) NOT NULL,
            IDPedido BIGINT NOT NULL,
            IDUsuario INT NOT NULL,

            ClaveIdempotencia VARCHAR(100)
                COLLATE Latin1_General_100_BIN2
                NOT NULL,

            HashSolicitud BINARY(32) NOT NULL,
            Motivo NVARCHAR(300) NOT NULL,
            MontoReembolso DECIMAL(19,2) NOT NULL,
            EstadoPedidoPosterior VARCHAR(20) NOT NULL,

            FechaCreacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_Devoluciones_Fecha
                DEFAULT (SYSUTCDATETIME()),

            CONSTRAINT PK_Devoluciones
                PRIMARY KEY (IDDevolucion),

            CONSTRAINT FK_Devoluciones_Pedidos
                FOREIGN KEY (IDPedido)
                REFERENCES dbo.Pedidos(IDPedido),

            CONSTRAINT FK_Devoluciones_Usuarios
                FOREIGN KEY (IDUsuario)
                REFERENCES dbo.Usuarios(IDUsuario),

            CONSTRAINT UQ_Devoluciones_Idempotencia
                UNIQUE (IDUsuario, ClaveIdempotencia),

            CONSTRAINT CK_Devoluciones_Monto
                CHECK (MontoReembolso >= 0),

            CONSTRAINT CK_Devoluciones_Estado
                CHECK (
                    EstadoPedidoPosterior IN (
                        'DEVUELTO_PARCIAL',
                        'DEVUELTO_TOTAL'
                    )
                ),

            CONSTRAINT CK_Devoluciones_Clave
                CHECK (LEN(ClaveIdempotencia) >= 16)
        );

        -- ==========================================
        -- DETALLES DE DEVOLUCION
        -- ==========================================

        CREATE TABLE dbo.DetallesDevolucion (
            IDDetalleDevolucion BIGINT IDENTITY(1,1) NOT NULL,
            IDDevolucion BIGINT NOT NULL,
            IDDetallePedido BIGINT NOT NULL,
            Cantidad INT NOT NULL,
            PrecioUnitario DECIMAL(19,2) NOT NULL,
            ImporteLinea DECIMAL(19,2) NOT NULL,

            CONSTRAINT PK_DetallesDevolucion
                PRIMARY KEY (IDDetalleDevolucion),

            CONSTRAINT FK_DetallesDevolucion_Devoluciones
                FOREIGN KEY (IDDevolucion)
                REFERENCES dbo.Devoluciones(IDDevolucion),

            CONSTRAINT FK_DetallesDevolucion_Pedidos
                FOREIGN KEY (IDDetallePedido)
                REFERENCES dbo.DetallesPedido(IDDetallePedido),

            CONSTRAINT UQ_DetallesDevolucion_Linea
                UNIQUE (IDDevolucion, IDDetallePedido),

            CONSTRAINT CK_DetallesDevolucion_Valores
                CHECK (
                    Cantidad > 0
                    AND PrecioUnitario >= 0
                    AND ImporteLinea = PrecioUnitario * Cantidad
                )
        );

        CREATE INDEX IX_Devoluciones_Pedido_Fecha
        ON dbo.Devoluciones (
            IDPedido,
            FechaCreacion DESC
        );

        CREATE INDEX IX_DetallesDevolucion_DetallePedido
        ON dbo.DetallesDevolucion (IDDetallePedido);

        -- ==========================================
        -- STORED PROCEDURE
        -- ==========================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Pedidos_RegistrarDevolucion
    @IDPedido BIGINT,
    @IDDetallePedido BIGINT,
    @IDUsuario INT,
    @Cantidad INT,
    @Motivo NVARCHAR(300),
    @ClaveIdempotencia VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IDPedido IS NULL OR @IDPedido <= 0
        THROW 69010, ''Pedido invalido.'', 1;

    IF @IDDetallePedido IS NULL OR @IDDetallePedido <= 0
        THROW 69011, ''Detalle de pedido invalido.'', 1;

    IF @IDUsuario IS NULL OR @IDUsuario <= 0
        THROW 69012, ''Usuario invalido.'', 1;

    IF @Cantidad IS NULL OR @Cantidad <= 0
        THROW 69013, ''Cantidad invalida.'', 1;

    IF @Motivo IS NULL
       OR LEN(LTRIM(RTRIM(@Motivo))) = 0
        THROW 69014, ''Debe indicar un motivo.'', 1;

    IF @ClaveIdempotencia IS NULL
       OR DATALENGTH(@ClaveIdempotencia) < 16
       OR DATALENGTH(@ClaveIdempotencia) > 100
        THROW 69015,
            ''Clave de idempotencia invalida.'', 1;

    SET @Motivo = LTRIM(RTRIM(@Motivo));

    DECLARE @Hash BINARY(32) = HASHBYTES(
        ''SHA2_256'',
        CONCAT(
            N''devolucion-v1|'',
            @IDPedido, N''|'',
            @IDDetallePedido, N''|'',
            @IDUsuario, N''|'',
            @Cantidad, N''|'',
            @Motivo
        )
    );

    DECLARE @Rol NVARCHAR(50);
    DECLARE @IDPropietario INT;
    DECLARE @EstadoAnterior VARCHAR(20);
    DECLARE @EstadoNuevo VARCHAR(20);

    DECLARE @IDDevolucion BIGINT;
    DECLARE @HashExistente BINARY(32);

    DECLARE @IDVariante INT;
    DECLARE @Vendida INT;
    DECLARE @DevueltaAntes INT;
    DECLARE @Precio DECIMAL(19,2);
    DECLARE @Monto DECIMAL(19,2);

    DECLARE @SaldoAnterior INT;
    DECLARE @SaldoNuevo BIGINT;
    DECLARE @Fecha DATETIME2(3);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Validar usuario activo.
        SELECT @Rol = r.Nombre
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1;

        IF @Rol IS NULL
            THROW 69016,
                ''Usuario no autorizado.'', 1;

        -- 2. Bloquear pedido.
        SELECT
            @IDPropietario = IDUsuario,
            @EstadoAnterior = Estado
        FROM dbo.Pedidos WITH (UPDLOCK, HOLDLOCK)
        WHERE IDPedido = @IDPedido;

        IF @IDPropietario IS NULL
            THROW 69017,
                ''Pedido no encontrado.'', 1;

        IF NOT (
            @Rol IN (''Administrador'', ''Operador'')
            OR (
                @Rol = ''Cliente''
                AND @IDPropietario = @IDUsuario
            )
        )
            THROW 69018,
                ''No tiene permisos sobre el pedido.'', 1;

        -- 3. Idempotencia: devolver resultado previo.
        SELECT
            @IDDevolucion = IDDevolucion,
            @HashExistente = HashSolicitud
        FROM dbo.Devoluciones WITH (UPDLOCK, HOLDLOCK)
        WHERE IDUsuario = @IDUsuario
          AND ClaveIdempotencia = @ClaveIdempotencia;

        IF @IDDevolucion IS NOT NULL
        BEGIN
            IF @HashExistente <> @Hash
                THROW 69019,
                    ''Clave utilizada para otra devolucion.'',
                    1;

            COMMIT TRANSACTION;

            SELECT
                d.IDDevolucion,
                d.IDPedido,
                dd.IDDetallePedido,
                dd.Cantidad,
                d.MontoReembolso,
                d.EstadoPedidoPosterior AS EstadoPedido,
                CAST(1 AS BIT) AS Reutilizado
            FROM dbo.Devoluciones d
            JOIN dbo.DetallesDevolucion dd
                ON dd.IDDevolucion = d.IDDevolucion
            WHERE d.IDDevolucion = @IDDevolucion;

            RETURN;
        END;

        -- 4. Solo devoluciones despues de entrega.
        IF @EstadoAnterior NOT IN (
            ''ENTREGADO'',
            ''DEVUELTO_PARCIAL''
        )
            THROW 69020,
                ''El pedido no admite devoluciones.'',
                1;

        -- Por ahora no hay cupones integrados.
        -- Evitar reembolsos superiores al pago real.
        IF EXISTS (
            SELECT 1
            FROM dbo.Pedidos
            WHERE IDPedido = @IDPedido
              AND Descuento <> 0
        )
            THROW 69021,
                ''Devolucion con descuento requiere calculo proporcional.'',
                1;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Pagos
            WHERE IDPedido = @IDPedido
              AND Estado = ''APROBADO''
        )
            THROW 69022,
                ''El pago no admite devolucion.'', 1;

        -- 5. Bloquear la linea vendida.
        SELECT
            @IDVariante = IDVariante,
            @Vendida = Cantidad,
            @DevueltaAntes = CantidadDevuelta,
            @Precio = PrecioUnitario
        FROM dbo.DetallesPedido WITH (UPDLOCK, HOLDLOCK)
        WHERE IDDetallePedido = @IDDetallePedido
          AND IDPedido = @IDPedido;

        IF @IDVariante IS NULL
            THROW 69023,
                ''Detalle no pertenece al pedido.'', 1;

        IF CONVERT(BIGINT, @DevueltaAntes)
           + @Cantidad > @Vendida
            THROW 69024,
                ''La cantidad supera las unidades pendientes de devolver.'',
                1;

        SET @Monto = CONVERT(
            DECIMAL(19,2),
            @Precio * @Cantidad
        );

        -- 6. Bloquear y validar existencia.
        SELECT @SaldoAnterior = CantidadFisica
        FROM dbo.Existencias WITH (UPDLOCK, HOLDLOCK)
        WHERE IDVariante = @IDVariante;

        IF @SaldoAnterior IS NULL
            THROW 69025,
                ''No existe inventario para la variante.'',
                1;

        SET @SaldoNuevo =
            CONVERT(BIGINT, @SaldoAnterior) + @Cantidad;

        IF @SaldoNuevo > 2147483647
            THROW 69026,
                ''El reintegro supera el limite de inventario.'',
                1;

        SET @Fecha = SYSUTCDATETIME();

        -- 7. Registrar cantidad devuelta.
        UPDATE dbo.DetallesPedido
        SET CantidadDevuelta = CantidadDevuelta + @Cantidad
        WHERE IDDetallePedido = @IDDetallePedido
          AND IDPedido = @IDPedido;

        IF @@ROWCOUNT <> 1
            THROW 69027,
                ''No se pudo actualizar el detalle.'', 1;

        -- 8. Determinar estado del pedido.
        IF EXISTS (
            SELECT 1
            FROM dbo.DetallesPedido
            WHERE IDPedido = @IDPedido
              AND CantidadDevuelta < Cantidad
        )
            SET @EstadoNuevo = ''DEVUELTO_PARCIAL'';
        ELSE
            SET @EstadoNuevo = ''DEVUELTO_TOTAL'';

        -- 9. Registrar devolucion y detalle.
        INSERT INTO dbo.Devoluciones (
            IDPedido,
            IDUsuario,
            ClaveIdempotencia,
            HashSolicitud,
            Motivo,
            MontoReembolso,
            EstadoPedidoPosterior,
            FechaCreacion
        )
        VALUES (
            @IDPedido,
            @IDUsuario,
            @ClaveIdempotencia,
            @Hash,
            @Motivo,
            @Monto,
            @EstadoNuevo,
            @Fecha
        );

        SET @IDDevolucion =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        INSERT INTO dbo.DetallesDevolucion (
            IDDevolucion,
            IDDetallePedido,
            Cantidad,
            PrecioUnitario,
            ImporteLinea
        )
        VALUES (
            @IDDevolucion,
            @IDDetallePedido,
            @Cantidad,
            @Precio,
            @Monto
        );

        -- 10. Reintegrar inventario.
        UPDATE dbo.Existencias
        SET
            CantidadFisica = CONVERT(INT, @SaldoNuevo),
            FechaActualizacion = @Fecha
        WHERE IDVariante = @IDVariante;

        IF @@ROWCOUNT <> 1
            THROW 69028,
                ''No fue posible reintegrar existencia.'',
                1;

        -- 11. Registrar kardex.
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
            @IDVariante,
            @IDUsuario,
            ''DEVOLUCION'',
            @Cantidad,
            @SaldoAnterior,
            CONVERT(INT, @SaldoNuevo),
            LEFT(
                CONCAT(
                    N''Devolucion pedido '',
                    @IDPedido, N'': '', @Motivo
                ),
                300
            ),
            @Fecha
        );

        -- 12. Actualizar pedido.
        IF @EstadoAnterior <> @EstadoNuevo
        BEGIN
            UPDATE dbo.Pedidos
            SET
                Estado = @EstadoNuevo,
                FechaActualizacion = @Fecha
            WHERE IDPedido = @IDPedido
              AND Estado = @EstadoAnterior;

            IF @@ROWCOUNT <> 1
                THROW 69029,
                    ''No fue posible actualizar el pedido.'',
                    1;

            INSERT INTO dbo.HistorialEstadosPedido (
                IDPedido,
                IDUsuario,
                EstadoAnterior,
                EstadoNuevo,
                Observacion,
                FechaCambio
            )
            VALUES (
                @IDPedido,
                @IDUsuario,
                @EstadoAnterior,
                @EstadoNuevo,
                @Motivo,
                @Fecha
            );
        END;

        -- 13. Pago simulado:
        -- solo marcar reembolso completo cuando
        -- todas las unidades hayan sido devueltas.
        IF @EstadoNuevo = ''DEVUELTO_TOTAL''
        BEGIN
            UPDATE dbo.Pagos
            SET Estado = ''REEMBOLSADO''
            WHERE IDPedido = @IDPedido
              AND Estado = ''APROBADO'';

            IF @@ROWCOUNT <> 1
                THROW 69030,
                    ''No se pudo registrar el reembolso total.'',
                    1;
        END;

        COMMIT TRANSACTION;

        SELECT
            @IDDevolucion AS IDDevolucion,
            @IDPedido AS IDPedido,
            @IDDetallePedido AS IDDetallePedido,
            @Cantidad AS Cantidad,
            @Monto AS MontoReembolso,
            @EstadoNuevo AS EstadoPedido,
            CAST(0 AS BIT) AS Reutilizado;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Pedidos_RegistrarDevolucion
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            30,
            N'030_OrderReturnsProcedure'
        );

        PRINT 'Migracion 030 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(N'dbo.Devoluciones', N'U') IS NULL
           OR OBJECT_ID(N'dbo.DetallesDevolucion', N'U') IS NULL
           OR OBJECT_ID(N'dbo.SP_Pedidos_RegistrarDevolucion', N'P') IS NULL
            THROW 69003,
                'Migracion registrada pero faltan objetos.',
                1;

        PRINT 'Migracion 030 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
