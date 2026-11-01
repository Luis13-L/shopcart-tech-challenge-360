USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- Validar dependencia
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 28
    )
        THROW 68001,
            'Primero ejecute la migracion 028.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 29
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Pedidos_CancelarPedido', N'P'
        ) IS NOT NULL
            THROW 68002,
                'El procedimiento ya existe.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Pedidos_CancelarPedido
    @IDPedido BIGINT,
    @IDUsuario INT,
    @Motivo NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 1. Validar parametros
    IF @IDPedido IS NULL OR @IDPedido <= 0
        THROW 68010, ''Pedido invalido.'', 1;

    IF @IDUsuario IS NULL OR @IDUsuario <= 0
        THROW 68011, ''Usuario invalido.'', 1;

    IF @Motivo IS NULL
       OR LEN(LTRIM(RTRIM(@Motivo))) = 0
        THROW 68012,
            ''Debe indicar un motivo de cancelacion.'', 1;

    SET @Motivo = LTRIM(RTRIM(@Motivo));

    DECLARE @Rol NVARCHAR(50);
    DECLARE @IDCliente INT;
    DECLARE @EstadoAnterior VARCHAR(20);
    DECLARE @EstadoPago VARCHAR(20);
    DECLARE @Fecha DATETIME2(3);

    DECLARE @Variante INT;
    DECLARE @Cantidad INT;
    DECLARE @SaldoAnterior INT;
    DECLARE @SaldoNuevo BIGINT;
    DECLARE @UltimaVariante INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ==========================================
        -- 2. AUTENTICACION Y AUTORIZACION
        -- ==========================================

        SELECT @Rol = r.Nombre
        FROM dbo.Usuarios AS u
        INNER JOIN dbo.Roles AS r
            ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1;

        IF @Rol IS NULL
            THROW 68013,
                ''Usuario no autorizado.'', 1;

        -- ==========================================
        -- 3. BLOQUEAR EL PEDIDO
        -- ==========================================

        SELECT
            @IDCliente = IDUsuario,
            @EstadoAnterior = Estado
        FROM dbo.Pedidos WITH (UPDLOCK, HOLDLOCK)
        WHERE IDPedido = @IDPedido;

        IF @IDCliente IS NULL
            THROW 68014,
                ''Pedido no encontrado.'', 1;

        IF NOT (
            @Rol IN (''Operador'', ''Administrador'')
            OR (
                @Rol = ''Cliente''
                AND @IDCliente = @IDUsuario
            )
        )
            THROW 68015,
                ''No tiene permisos sobre este pedido.'',
                1;

        -- ==========================================
        -- 4. EVITAR REINTEGROS DUPLICADOS
        -- ==========================================

        IF @EstadoAnterior = ''CANCELADO''
        BEGIN
            COMMIT TRANSACTION;

            SELECT
                @IDPedido AS IDPedido,
                ''CANCELADO'' AS EstadoAnterior,
                ''CANCELADO'' AS EstadoNuevo,
                CAST(1 AS BIT) AS YaCancelado;

            RETURN;
        END;

        -- No cancelar pedidos despachados.
        IF @EstadoAnterior NOT IN (
            ''PAGADO'',
            ''PREPARANDO''
        )
            THROW 68016,
                ''El pedido ya no puede cancelarse.'',
                1;

        -- ==========================================
        -- 5. VALIDAR EL PAGO SIMULADO
        -- ==========================================

        SELECT @EstadoPago = Estado
        FROM dbo.Pagos WITH (UPDLOCK, HOLDLOCK)
        WHERE IDPedido = @IDPedido;

        IF @EstadoPago IS NULL
           OR @EstadoPago <> ''APROBADO''
            THROW 68017,
                ''El pago no admite cancelacion.'',
                1;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.DetallesPedido
            WHERE IDPedido = @IDPedido
        )
            THROW 68018,
                ''El pedido no tiene detalles.'', 1;

        IF EXISTS (
            SELECT 1
            FROM dbo.DetallesPedido
            WHERE IDPedido = @IDPedido
              AND CantidadDevuelta > 0
        )
            THROW 68019,
                ''Existen devoluciones previas.'', 1;

        SET @Fecha = SYSUTCDATETIME();

        -- ==========================================
        -- 6. REINTEGRAR INVENTARIO Y KARDEX
        -- ==========================================

        -- Se recorren las variantes en orden
        -- ascendente para mantener un orden
        -- consistente de bloqueos.

        WHILE EXISTS (
            SELECT 1
            FROM dbo.DetallesPedido
            WHERE IDPedido = @IDPedido
              AND IDVariante > @UltimaVariante
        )
        BEGIN
            SELECT TOP (1)
                @Variante = IDVariante,
                @Cantidad = Cantidad
            FROM dbo.DetallesPedido WITH (HOLDLOCK)
            WHERE IDPedido = @IDPedido
              AND IDVariante > @UltimaVariante
            ORDER BY IDVariante;

            SET @SaldoAnterior = NULL;

            SELECT
                @SaldoAnterior = CantidadFisica
            FROM dbo.Existencias
                WITH (UPDLOCK, HOLDLOCK)
            WHERE IDVariante = @Variante;

            IF @SaldoAnterior IS NULL
                THROW 68020,
                    ''No existe inventario para la variante.'',
                    1;

            SET @SaldoNuevo =
                CONVERT(BIGINT, @SaldoAnterior)
                + CONVERT(BIGINT, @Cantidad);

            IF @SaldoNuevo > 2147483647
                THROW 68021,
                    ''El reintegro supera el limite de inventario.'',
                    1;

            UPDATE dbo.Existencias
            SET
                CantidadFisica = CONVERT(
                    INT, @SaldoNuevo
                ),
                FechaActualizacion = @Fecha
            WHERE IDVariante = @Variante;

            IF @@ROWCOUNT <> 1
                THROW 68022,
                    ''No fue posible reintegrar inventario.'',
                    1;

            -- DEVOLUCION es un tipo positivo
            -- permitido por nuestro kardex.
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
                ''DEVOLUCION'',
                @Cantidad,
                @SaldoAnterior,
                CONVERT(INT, @SaldoNuevo),
                LEFT(
                    CONCAT(
                        N''Cancelacion pedido '',
                        @IDPedido,
                        N'': '',
                        @Motivo
                    ),
                    300
                ),
                @Fecha
            );

            SET @UltimaVariante = @Variante;
        END;

        -- ==========================================
        -- 7. REVERTIR EL PAGO SIMULADO
        -- ==========================================

        UPDATE dbo.Pagos
        SET Estado = ''REEMBOLSADO''
        WHERE IDPedido = @IDPedido
          AND Estado = ''APROBADO'';

        IF @@ROWCOUNT <> 1
            THROW 68023,
                ''No fue posible revertir el pago.'',
                1;

        -- ==========================================
        -- 8. CANCELAR EL PEDIDO
        -- ==========================================

        UPDATE dbo.Pedidos
        SET
            Estado = ''CANCELADO'',
            FechaActualizacion = @Fecha
        WHERE IDPedido = @IDPedido
          AND Estado = @EstadoAnterior;

        IF @@ROWCOUNT <> 1
            THROW 68024,
                ''No fue posible cancelar el pedido.'',
                1;

        -- ==========================================
        -- 9. REGISTRAR HISTORIAL
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
            @IDPedido,
            @IDUsuario,
            @EstadoAnterior,
            ''CANCELADO'',
            @Motivo,
            @Fecha
        );

        -- ==========================================
        -- 10. CONFIRMAR TODO
        -- ==========================================

        COMMIT TRANSACTION;

        SELECT
            @IDPedido AS IDPedido,
            @EstadoAnterior AS EstadoAnterior,
            ''CANCELADO'' AS EstadoNuevo,
            CAST(0 AS BIT) AS YaCancelado,
            @Fecha AS FechaCambio;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Pedidos_CancelarPedido
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            29,
            N'029_CancelOrderProcedure'
        );

        PRINT 'Migracion 029 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Pedidos_CancelarPedido',
            N'P'
        ) IS NULL
            THROW 68003,
                'Migracion registrada pero falta el SP.',
                1;

        PRINT 'Migracion 029 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
