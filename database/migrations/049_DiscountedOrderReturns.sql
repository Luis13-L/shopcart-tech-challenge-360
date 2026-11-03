USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM dbo.SchemaMigrations
    WHERE Numero = 48
)
    THROW 78900, 'Ejecute primero la migracion 048.', 1;
GO

CREATE OR ALTER PROCEDURE dbo.SP_Pedidos_RegistrarDevolucion
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
        THROW 69010, 'Pedido invalido.', 1;

    IF @IDDetallePedido IS NULL OR @IDDetallePedido <= 0
        THROW 69011, 'Detalle de pedido invalido.', 1;

    IF @IDUsuario IS NULL OR @IDUsuario <= 0
        THROW 69012, 'Usuario invalido.', 1;

    IF @Cantidad IS NULL OR @Cantidad <= 0
        THROW 69013, 'Cantidad invalida.', 1;

    IF NULLIF(LTRIM(RTRIM(@Motivo)), N'') IS NULL
        THROW 69014, 'Motivo obligatorio.', 1;

    IF @ClaveIdempotencia IS NULL
       OR DATALENGTH(@ClaveIdempotencia) NOT BETWEEN 16 AND 100
        THROW 69015, 'Clave de idempotencia invalida.', 1;

    SET @Motivo = LTRIM(RTRIM(@Motivo));

    -- Se conserva el contrato de idempotencia anterior.
    DECLARE @Hash BINARY(32) = HASHBYTES(
        'SHA2_256',
        CONCAT(
            N'devolucion-v1|',
            @IDPedido, N'|',
            @IDDetallePedido, N'|',
            @IDUsuario, N'|',
            @Cantidad, N'|',
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
    DECLARE @ImporteLinea DECIMAL(19,2);

    DECLARE @SubtotalPedido DECIMAL(19,2);
    DECLARE @TotalPedido DECIMAL(19,2);
    DECLARE @AcumuladoAnterior DECIMAL(38,2);
    DECLARE @AcumuladoActual DECIMAL(38,2);
    DECLARE @NetoLinea DECIMAL(19,2);

    DECLARE @Monto DECIMAL(19,2);
    DECLARE @TotalReembolsado DECIMAL(38,2);

    DECLARE @SaldoAnterior INT;
    DECLARE @SaldoNuevo BIGINT;
    DECLARE @Fecha DATETIME2(3);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Autorizar usuario.
        SELECT @Rol = r.Nombre
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1;

        IF @Rol IS NULL
            THROW 69016, 'Usuario no autorizado.', 1;

        -- 2. Bloquear pedido y recuperar montos historicos.
        SELECT
            @IDPropietario = IDUsuario,
            @EstadoAnterior = Estado,
            @SubtotalPedido = Subtotal,
            @TotalPedido = Total
        FROM dbo.Pedidos WITH (UPDLOCK, HOLDLOCK)
        WHERE IDPedido = @IDPedido;

        IF @IDPropietario IS NULL
            THROW 69017, 'Pedido no encontrado.', 1;

        IF NOT (
            @Rol IN ('Administrador', 'Operador')
            OR (
                @Rol = 'Cliente'
                AND @IDPropietario = @IDUsuario
            )
        )
            THROW 69018,
                'No tiene permisos sobre el pedido.', 1;

        -- 3. Idempotencia: recuperar un resultado previo.
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
                    'Clave utilizada para otra devolucion.', 1;

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
            INNER JOIN dbo.DetallesDevolucion dd
                ON dd.IDDevolucion = d.IDDevolucion
            WHERE d.IDDevolucion = @IDDevolucion;

            RETURN;
        END;

        -- 4. Validaciones del pedido y pago.
        IF @EstadoAnterior NOT IN (
            'ENTREGADO', 'DEVUELTO_PARCIAL'
        )
            THROW 69020,
                'El pedido no admite devoluciones.', 1;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Pagos
            WHERE IDPedido = @IDPedido
              AND Estado = 'APROBADO'
        )
            THROW 69022,
                'El pago no admite devolucion.', 1;

        -- 5. Bloquear el detalle vendido.
        SELECT
            @IDVariante = IDVariante,
            @Vendida = Cantidad,
            @DevueltaAntes = CantidadDevuelta,
            @Precio = PrecioUnitario,
            @ImporteLinea = ImporteLinea
        FROM dbo.DetallesPedido WITH (UPDLOCK, HOLDLOCK)
        WHERE IDDetallePedido = @IDDetallePedido
          AND IDPedido = @IDPedido;

        IF @IDVariante IS NULL
            THROW 69023,
                'Detalle no pertenece al pedido.', 1;

        IF CONVERT(BIGINT, @DevueltaAntes)
           + @Cantidad > @Vendida
            THROW 69024,
                'La cantidad supera lo pendiente.', 1;

        -- 6. Verificar coherencia monetaria historica.
        IF @SubtotalPedido < 0
           OR @TotalPedido < 0
           OR @TotalPedido > @SubtotalPedido
           OR (
                SELECT ISNULL(
                    SUM(CONVERT(DECIMAL(38,2), ImporteLinea)), 0
                )
                FROM dbo.DetallesPedido
                WHERE IDPedido = @IDPedido
           ) <> @SubtotalPedido
            THROW 69031,
                'Los importes del pedido no son coherentes.', 1;

        -- 7. Distribucion proporcional del TOTAL PAGADO.
        -- El redondeo acumulado evita perder centavos
        -- entre varias lineas del mismo pedido.
        SELECT
            @AcumuladoAnterior = ISNULL(
                SUM(CONVERT(DECIMAL(38,2), ImporteLinea)), 0
            )
        FROM dbo.DetallesPedido
        WHERE IDPedido = @IDPedido
          AND IDDetallePedido < @IDDetallePedido;

        SET @AcumuladoActual =
            @AcumuladoAnterior + @ImporteLinea;

        IF @SubtotalPedido = 0
            SET @NetoLinea = 0;
        ELSE
            SET @NetoLinea = CONVERT(
                DECIMAL(19,2),
                ROUND(
                    @AcumuladoActual * @TotalPedido
                    / @SubtotalPedido, 2
                )
                -
                ROUND(
                    @AcumuladoAnterior * @TotalPedido
                    / @SubtotalPedido, 2
                )
            );

        -- 8. Reembolso incremental de la linea.
        -- Las devoluciones parciales sucesivas
        -- suman el neto exacto asignado a la linea.
        SET @Monto = CONVERT(
            DECIMAL(19,2),
            ROUND(
                @NetoLinea
                * (CONVERT(BIGINT, @DevueltaAntes) + @Cantidad)
                / @Vendida, 2
            )
            -
            ROUND(
                @NetoLinea * @DevueltaAntes
                / @Vendida, 2
            )
        );

        -- Comprobacion global adicional.
        SELECT @TotalReembolsado = ISNULL(
            SUM(CONVERT(DECIMAL(38,2), MontoReembolso)), 0
        )
        FROM dbo.Devoluciones WITH (UPDLOCK, HOLDLOCK)
        WHERE IDPedido = @IDPedido;

        IF @Monto < 0
           OR @TotalReembolsado + @Monto > @TotalPedido
            THROW 69032,
                'El reembolso supera el importe pagado.', 1;

        -- 9. Bloquear existencias.
        SELECT @SaldoAnterior = CantidadFisica
        FROM dbo.Existencias WITH (UPDLOCK, HOLDLOCK)
        WHERE IDVariante = @IDVariante;

        IF @SaldoAnterior IS NULL
            THROW 69025,
                'No existe inventario para la variante.', 1;

        SET @SaldoNuevo =
            CONVERT(BIGINT, @SaldoAnterior) + @Cantidad;

        IF @SaldoNuevo > 2147483647
            THROW 69026,
                'El reintegro supera el limite.', 1;

        SET @Fecha = SYSUTCDATETIME();

        -- 10. Registrar cantidad devuelta.
        UPDATE dbo.DetallesPedido
        SET CantidadDevuelta = CantidadDevuelta + @Cantidad
        WHERE IDDetallePedido = @IDDetallePedido
          AND IDPedido = @IDPedido;

        IF @@ROWCOUNT <> 1
            THROW 69027,
                'No se pudo actualizar el detalle.', 1;

        -- 11. Determinar estado resultante.
        IF EXISTS (
            SELECT 1
            FROM dbo.DetallesPedido
            WHERE IDPedido = @IDPedido
              AND CantidadDevuelta < Cantidad
        )
            SET @EstadoNuevo = 'DEVUELTO_PARCIAL';
        ELSE
            SET @EstadoNuevo = 'DEVUELTO_TOTAL';

        -- 12. Registrar devolucion.
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

        -- Se conserva el importe BRUTO de la linea
        -- en DetallesDevolucion. El dinero devuelto
        -- realmente esta en Devoluciones.MontoReembolso.
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
            CONVERT(DECIMAL(19,2), @Precio * @Cantidad)
        );

        -- 13. Reintegrar existencias y kardex.
        UPDATE dbo.Existencias
        SET
            CantidadFisica = CONVERT(INT, @SaldoNuevo),
            FechaActualizacion = @Fecha
        WHERE IDVariante = @IDVariante;

        IF @@ROWCOUNT <> 1
            THROW 69028,
                'No se pudo reintegrar inventario.', 1;

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
            'DEVOLUCION',
            @Cantidad,
            @SaldoAnterior,
            CONVERT(INT, @SaldoNuevo),
            LEFT(
                CONCAT(
                    N'Devolucion pedido ',
                    @IDPedido, N': ', @Motivo
                ),
                300
            ),
            @Fecha
        );

        -- 14. Cambiar estado e insertar historial.
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
                    'No se pudo actualizar el pedido.', 1;

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

        -- 15. Reembolso completo simulado.
        IF @EstadoNuevo = 'DEVUELTO_TOTAL'
        BEGIN
            UPDATE dbo.Pagos
            SET Estado = 'REEMBOLSADO'
            WHERE IDPedido = @IDPedido
              AND Estado = 'APROBADO';

            IF @@ROWCOUNT <> 1
                THROW 69030,
                    'No se pudo registrar el reembolso total.', 1;
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
GO

BEGIN TRY
    BEGIN TRANSACTION;

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Pedidos_RegistrarDevolucion
    TO [shopcart_api];

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 49
    )
    BEGIN
        INSERT INTO dbo.SchemaMigrations (Numero, Nombre)
        VALUES (49, N'049_DiscountedOrderReturns');
    END;

    COMMIT TRANSACTION;

    PRINT 'Migracion 049 aplicada correctamente.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
