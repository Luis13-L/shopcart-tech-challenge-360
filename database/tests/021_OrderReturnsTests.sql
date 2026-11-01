USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- =============================================
-- TEST 021: DEVOLUCIONES PARCIALES Y TOTALES
--
-- Escenario:
-- Carrito 12 con 3 unidades de variante 4.
-- Compra -> Entrega -> Devolucion 1 unidad
-- -> Reintento -> Devolucion 2 unidades.
--
-- Los cambios se revierten al finalizar.
-- Ejecutar exclusivamente en desarrollo.
-- =============================================

DECLARE @IDCarrito BIGINT = 12;
DECLARE @IDVariante INT = 4;

DECLARE @IDCliente INT;
DECLARE @IDAdmin INT;
DECLARE @IDDireccion INT;
DECLARE @IDReserva BIGINT;
DECLARE @IDPedido BIGINT;
DECLARE @IDDetallePedido BIGINT;

DECLARE @Cantidad INT;
DECLARE @FisicaAntes INT;
DECLARE @FisicaAhora INT;
DECLARE @TotalEsperado DECIMAL(19,2);

DECLARE @ClaveCheckout VARCHAR(100) =
    CONVERT(VARCHAR(36), NEWID());

DECLARE @ClaveDevolucion1 VARCHAR(100) =
    CONVERT(VARCHAR(36), NEWID());

DECLARE @ClaveDevolucion2 VARCHAR(100) =
    CONVERT(VARCHAR(36), NEWID());

DECLARE @ClaveDevolucion3 VARCHAR(100) =
    CONVERT(VARCHAR(36), NEWID());

-- Tablas para capturar resultados de los SP.
DECLARE @Checkout TABLE (
    IDPedido BIGINT,
    IDCarrito BIGINT,
    IDReserva BIGINT,
    Estado VARCHAR(20),
    Subtotal DECIMAL(19,2),
    Descuento DECIMAL(19,2),
    Total DECIMAL(19,2),
    Reutilizado BIT
);

DECLARE @PrimeraDevolucion TABLE (
    IDDevolucion BIGINT,
    IDPedido BIGINT,
    IDDetallePedido BIGINT,
    Cantidad INT,
    MontoReembolso DECIMAL(19,2),
    EstadoPedido VARCHAR(20),
    Reutilizado BIT
);

DECLARE @Reintento TABLE (
    IDDevolucion BIGINT,
    IDPedido BIGINT,
    IDDetallePedido BIGINT,
    Cantidad INT,
    MontoReembolso DECIMAL(19,2),
    EstadoPedido VARCHAR(20),
    Reutilizado BIT
);

DECLARE @SegundaDevolucion TABLE (
    IDDevolucion BIGINT,
    IDPedido BIGINT,
    IDDetallePedido BIGINT,
    Cantidad INT,
    MontoReembolso DECIMAL(19,2),
    EstadoPedido VARCHAR(20),
    Reutilizado BIT
);

BEGIN TRY

    -- =========================================
    -- 1. VALIDAR PRECONDICIONES
    -- =========================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 30
    )
        THROW 69101,
            'Primero ejecute la migracion 030.',
            1;

    SELECT @IDCliente = IDUsuario
    FROM dbo.Carritos
    WHERE IDCarrito = @IDCarrito
      AND Estado = 'ACTIVO';

    IF @IDCliente IS NULL
        THROW 69102,
            'El carrito 12 no esta activo.',
            1;

    SELECT @Cantidad = Cantidad
    FROM dbo.DetallesCarrito
    WHERE IDCarrito = @IDCarrito
      AND IDVariante = @IDVariante;

    IF @Cantidad <> 3 OR @Cantidad IS NULL
        THROW 69103,
            'El carrito debe contener 3 unidades.',
            1;

    IF (
        SELECT COUNT(*)
        FROM dbo.DetallesCarrito
        WHERE IDCarrito = @IDCarrito
    ) <> 1
        THROW 69104,
            'La prueba requiere una sola linea.',
            1;

    SELECT TOP (1)
        @IDAdmin = u.IDUsuario
    FROM dbo.Usuarios u
    INNER JOIN dbo.Roles r
        ON r.IDRol = u.IDRol
    WHERE r.Nombre = 'Administrador'
      AND u.Activo = 1
    ORDER BY u.IDUsuario;

    IF @IDAdmin IS NULL
        THROW 69105,
            'No existe administrador activo.',
            1;

    SELECT @FisicaAntes = CantidadFisica
    FROM dbo.Existencias
    WHERE IDVariante = @IDVariante;

    IF @FisicaAntes IS NULL
       OR @FisicaAntes < @Cantidad
        THROW 69106,
            'Inventario fisico insuficiente.',
            1;

    -- Evitar interferir con reservas vigentes.
    IF EXISTS (
        SELECT 1
        FROM dbo.ReservasInventario r
        INNER JOIN dbo.DetallesReserva d
            ON d.IDReserva = r.IDReserva
        WHERE d.IDVariante = @IDVariante
          AND r.Estado = 'ACTIVA'
          AND r.ExpiraEn > SYSUTCDATETIME()
    )
        THROW 69107,
            'Existen reservas vigentes para la variante.',
            1;

    SELECT @TotalEsperado = CONVERT(
        DECIMAL(19,2),
        v.PrecioActual * @Cantidad
    )
    FROM dbo.Variantes v
    WHERE v.IDVariante = @IDVariante;

    IF @TotalEsperado IS NULL
        THROW 69108,
            'No se encontro el precio de la variante.',
            1;

    -- =========================================
    -- 2. INICIAR TRANSACCION DE PRUEBA
    -- =========================================

    BEGIN TRANSACTION;

    -- Crear direccion ficticia temporal.
    INSERT INTO dbo.Direcciones (
        IDUsuario,
        Destinatario,
        Telefono,
        Departamento,
        Municipio,
        DireccionLinea1,
        Referencia,
        Activa,
        FechaCreacion
    )
    VALUES (
        @IDCliente,
        N'Cliente prueba devoluciones',
        N'00000000',
        N'Guatemala',
        N'Guatemala',
        N'Direccion temporal de pruebas',
        N'Test 021',
        1,
        SYSUTCDATETIME()
    );

    SET @IDDireccion =
        CONVERT(INT, SCOPE_IDENTITY());

    -- =========================================
    -- 3. RESERVAR INVENTARIO
    -- =========================================

    EXEC dbo.SP_Inventario_ReservarExistencia
        @IDCarrito = @IDCarrito,
        @IDUsuario = @IDCliente,
        @IDReserva = @IDReserva OUTPUT;

    IF @IDReserva IS NULL
        THROW 69109,
            'No se genero la reserva.',
            1;

    -- =========================================
    -- 4. CONFIRMAR LA COMPRA
    -- =========================================

    INSERT INTO @Checkout
    EXEC dbo.SP_Pedidos_ConfirmarCheckout
        @IDUsuario = @IDCliente,
        @IDReserva = @IDReserva,
        @IDDireccion = @IDDireccion,
        @ClaveIdempotencia = @ClaveCheckout,
        @TotalEsperado = @TotalEsperado;

    SELECT @IDPedido = IDPedido
    FROM @Checkout;

    IF @IDPedido IS NULL
        THROW 69110,
            'No se creo el pedido.',
            1;

    SELECT @IDDetallePedido = IDDetallePedido
    FROM dbo.DetallesPedido
    WHERE IDPedido = @IDPedido
      AND IDVariante = @IDVariante;

    IF @IDDetallePedido IS NULL
        THROW 69111,
            'No se genero el detalle del pedido.',
            1;

    -- Comprobar descuento fisico de la compra.
    SELECT @FisicaAhora = CantidadFisica
    FROM dbo.Existencias
    WHERE IDVariante = @IDVariante;

    IF @FisicaAhora <> @FisicaAntes - 3
        THROW 69112,
            'La compra desconto inventario incorrectamente.',
            1;

    -- =========================================
    -- 5. LLEVAR EL PEDIDO HASTA ENTREGADO
    -- =========================================

    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @IDPedido,
        @IDUsuario = @IDAdmin,
        @EstadoNuevo = 'PREPARANDO',
        @Observacion = N'Test 021: preparacion';

    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @IDPedido,
        @IDUsuario = @IDAdmin,
        @EstadoNuevo = 'DESPACHADO',
        @Observacion = N'Test 021: despacho';

    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @IDPedido,
        @IDUsuario = @IDAdmin,
        @EstadoNuevo = 'ENTREGADO',
        @Observacion = N'Test 021: entrega';

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pedidos
        WHERE IDPedido = @IDPedido
          AND Estado = 'ENTREGADO'
    )
        THROW 69113,
            'El pedido no llego a ENTREGADO.',
            1;

    -- =========================================
    -- 6. PRIMERA DEVOLUCION: 1 UNIDAD
    -- =========================================

    INSERT INTO @PrimeraDevolucion
    EXEC dbo.SP_Pedidos_RegistrarDevolucion
        @IDPedido = @IDPedido,
        @IDDetallePedido = @IDDetallePedido,
        @IDUsuario = @IDCliente,
        @Cantidad = 1,
        @Motivo = N'Prueba devolucion parcial',
        @ClaveIdempotencia = @ClaveDevolucion1;

    IF NOT EXISTS (
        SELECT 1
        FROM @PrimeraDevolucion
        WHERE EstadoPedido = 'DEVUELTO_PARCIAL'
          AND Cantidad = 1
          AND Reutilizado = 0
    )
        THROW 69114,
            'Fallo la devolucion parcial.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.DetallesPedido
        WHERE IDDetallePedido = @IDDetallePedido
          AND CantidadDevuelta = 1
    )
        THROW 69115,
            'CantidadDevuelta incorrecta.',
            1;

    -- =========================================
    -- 7. REPETIR LA MISMA DEVOLUCION
    -- =========================================

    INSERT INTO @Reintento
    EXEC dbo.SP_Pedidos_RegistrarDevolucion
        @IDPedido = @IDPedido,
        @IDDetallePedido = @IDDetallePedido,
        @IDUsuario = @IDCliente,
        @Cantidad = 1,
        @Motivo = N'Prueba devolucion parcial',
        @ClaveIdempotencia = @ClaveDevolucion1;

    IF NOT EXISTS (
        SELECT 1
        FROM @PrimeraDevolucion p
        CROSS JOIN @Reintento r
        WHERE p.IDDevolucion = r.IDDevolucion
          AND r.Reutilizado = 1
    )
        THROW 69116,
            'Fallo la idempotencia de devolucion.',
            1;

    -- La cantidad no debe incrementarse.
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.DetallesPedido
        WHERE IDDetallePedido = @IDDetallePedido
          AND CantidadDevuelta = 1
    )
        THROW 69117,
            'El reintento duplico las unidades.',
            1;

    -- =========================================
    -- 8. DEVOLUCION FINAL: 2 UNIDADES
    -- =========================================

    INSERT INTO @SegundaDevolucion
    EXEC dbo.SP_Pedidos_RegistrarDevolucion
        @IDPedido = @IDPedido,
        @IDDetallePedido = @IDDetallePedido,
        @IDUsuario = @IDCliente,
        @Cantidad = 2,
        @Motivo = N'Prueba devolucion total',
        @ClaveIdempotencia = @ClaveDevolucion2;

    IF NOT EXISTS (
        SELECT 1
        FROM @SegundaDevolucion
        WHERE Cantidad = 2
          AND EstadoPedido = 'DEVUELTO_TOTAL'
          AND Reutilizado = 0
    )
        THROW 69118,
            'Fallo la devolucion total.',
            1;

    -- =========================================
    -- 9. VALIDACIONES FINALES
    -- =========================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.DetallesPedido
        WHERE IDDetallePedido = @IDDetallePedido
          AND Cantidad = 3
          AND CantidadDevuelta = 3
    )
        THROW 69119,
            'Las cantidades devueltas no coinciden.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pedidos
        WHERE IDPedido = @IDPedido
          AND Estado = 'DEVUELTO_TOTAL'
    )
        THROW 69120,
            'Estado final del pedido incorrecto.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pagos
        WHERE IDPedido = @IDPedido
          AND Estado = 'REEMBOLSADO'
    )
        THROW 69121,
            'El pago simulado no fue reembolsado.',
            1;

    -- La cantidad fisica debe volver
    -- al valor anterior a la compra.
    SELECT @FisicaAhora = CantidadFisica
    FROM dbo.Existencias
    WHERE IDVariante = @IDVariante;

    IF @FisicaAhora <> @FisicaAntes
        THROW 69122,
            'Inventario reintegrado incorrectamente.',
            1;

    -- Deben existir exactamente dos devoluciones.
    IF (
        SELECT COUNT(*)
        FROM dbo.Devoluciones
        WHERE IDPedido = @IDPedido
    ) <> 2
        THROW 69123,
            'Se duplicaron las devoluciones.',
            1;

    -- Verificar el kardex de las dos devoluciones.
    IF (
        SELECT COUNT(*)
        FROM dbo.MovimientosInventario
        WHERE TipoMovimiento = 'DEVOLUCION'
          AND Motivo LIKE CONCAT(
              N'Devolucion pedido ',
              @IDPedido,
              N':%'
          )
    ) <> 2
        THROW 69124,
            'Cantidad incorrecta de movimientos de kardex.',
            1;

    IF (
        SELECT ISNULL(SUM(CantidadFirmada), 0)
        FROM dbo.MovimientosInventario
        WHERE TipoMovimiento = 'DEVOLUCION'
          AND Motivo LIKE CONCAT(
              N'Devolucion pedido ',
              @IDPedido,
              N':%'
          )
    ) <> 3
        THROW 69125,
            'El kardex reintegro una cantidad incorrecta.',
            1;

    -- Verificar ambos cambios de estado.
    IF (
        SELECT COUNT(*)
        FROM dbo.HistorialEstadosPedido
        WHERE IDPedido = @IDPedido
          AND EstadoNuevo IN (
              'DEVUELTO_PARCIAL',
              'DEVUELTO_TOTAL'
          )
    ) <> 2
        THROW 69126,
            'Historial de devoluciones incorrecto.',
            1;

    -- =========================================
    -- 10. MOSTRAR RESULTADOS
    -- =========================================

    SELECT
        'OK: devolucion parcial' AS Prueba,
        IDDevolucion,
        Cantidad,
        EstadoPedido,
        Reutilizado
    FROM @PrimeraDevolucion;

    SELECT
        'OK: idempotencia' AS Prueba,
        IDDevolucion,
        Cantidad,
        EstadoPedido,
        Reutilizado
    FROM @Reintento;

    SELECT
        'OK: devolucion total' AS Prueba,
        IDDevolucion,
        Cantidad,
        EstadoPedido,
        Reutilizado
    FROM @SegundaDevolucion;

    SELECT
        @IDPedido AS IDPedido,
        @FisicaAntes AS ExistenciaInicial,
        @FisicaAhora AS ExistenciaFinal,
        'OK: inventario y kardex coherentes'
            AS Resultado;

    -- =========================================
-- 11. PRUEBA NEGATIVA
-- Intentar devolver una cuarta unidad.
-- Usamos una clave NUEVA.
-- =========================================

EXEC dbo.SP_Pedidos_RegistrarDevolucion
    @IDPedido = @IDPedido,
    @IDDetallePedido = @IDDetallePedido,
    @IDUsuario = @IDCliente,
    @Cantidad = 1,
    @Motivo = N'Intento de devolucion excesiva',
    @ClaveIdempotencia = @ClaveDevolucion3;

    -- Si el SP devuelve exito, la prueba falla.
    -- Esta instruccion no debe alcanzarse.
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW 69127,
        'ERROR: se permitio una devolucion adicional.',
        1;

END TRY
BEGIN CATCH

    DECLARE @CodigoError INT = ERROR_NUMBER();
    DECLARE @MensajeError NVARCHAR(4000) =
        ERROR_MESSAGE();

    -- Si falla cualquier operacion,
    -- revertir toda la compra de prueba.
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF @CodigoError = 69020
    BEGIN
        SELECT
            @CodigoError AS CodigoError,
            @MensajeError AS MensajeError,
            'OK: devolucion excesiva rechazada'
                AS Resultado;

        SELECT
            'OK: ROLLBACK completado'
                AS Limpieza;
    END
    ELSE
    BEGIN
        THROW;
    END;

END CATCH;
GO
