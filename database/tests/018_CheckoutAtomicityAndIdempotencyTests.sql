USE ShopCartDB;
GO

-- PRUEBA DE DESARROLLO:
-- Ejecuta checkout completo y revierte todo.
-- Requiere carrito 11 ACTIVO, con productos
-- y stock suficiente.
-- Ejecutar solo en base local.

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDUsuario INT;
DECLARE @IDDireccion INT;
DECLARE @IDReserva BIGINT;
DECLARE @IDPedido BIGINT;
DECLARE @Cantidad INT;
DECLARE @FisicaAnterior INT;
DECLARE @FisicaPosterior INT;
DECLARE @TotalEsperado DECIMAL(19,2);

DECLARE @Clave VARCHAR(100) =
    CONVERT(VARCHAR(36), NEWID());

BEGIN TRY

    -- ==========================================
    -- 1. VALIDAR MIGRACION
    -- ==========================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 27
    )
        THROW 66100,
            'Primero ejecute la migracion 027.', 1;

    -- ==========================================
    -- 2. OBTENER CLIENTE DEL CARRITO
    -- ==========================================

    SELECT @IDUsuario = IDUsuario
    FROM dbo.Carritos
    WHERE IDCarrito = 11
      AND Estado = 'ACTIVO';

    IF @IDUsuario IS NULL
        THROW 66101,
            'El carrito 11 no esta ACTIVO.', 1;

    -- ==========================================
    -- 3. COMPROBAR PRODUCTOS
    -- ==========================================

    SELECT @Cantidad = Cantidad
    FROM dbo.DetallesCarrito
    WHERE IDCarrito = 11
      AND IDVariante = 4;

    IF @Cantidad IS NULL
       OR @Cantidad <= 0
        THROW 66102,
            'El carrito 11 no tiene la variante 4.',
            1;

    IF (
        SELECT COUNT(*)
        FROM dbo.DetallesCarrito
        WHERE IDCarrito = 11
    ) <> 1
        THROW 66103,
            'El test espera una sola linea en carrito 11.',
            1;

    -- ==========================================
    -- 4. CONSULTAR EXISTENCIA INICIAL
    -- ==========================================

    SELECT @FisicaAnterior = CantidadFisica
    FROM dbo.Existencias
    WHERE IDVariante = 4;

    -- ==========================================
    -- 5. CALCULAR TOTAL ESPERADO
    -- ==========================================

    SELECT @TotalEsperado = SUM(
        CONVERT(
            DECIMAL(19,2),
            v.PrecioActual * dc.Cantidad
        )
    )
    FROM dbo.DetallesCarrito AS dc
    INNER JOIN dbo.Variantes AS v
        ON v.IDVariante = dc.IDVariante
    WHERE dc.IDCarrito = 11;

    BEGIN TRANSACTION;

    -- ==========================================
    -- 6. CREAR DIRECCION TEMPORAL
    -- ==========================================

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
        @IDUsuario,
        N'Cliente de prueba',
        N'00000000',
        N'Guatemala',
        N'Guatemala',
        N'Direccion ficticia de prueba 123',
        N'Solo pruebas automatizadas',
        1,
        SYSUTCDATETIME()
    );

    SET @IDDireccion = CONVERT(
        INT,
        SCOPE_IDENTITY()
    );

    -- ==========================================
    -- 7. RESERVAR INVENTARIO
    -- ==========================================

    EXEC dbo.SP_Inventario_ReservarExistencia
        @IDCarrito = 11,
        @IDUsuario = @IDUsuario,
        @IDReserva = @IDReserva OUTPUT;

    -- ==========================================
    -- 8. PRIMERA CONFIRMACION
    -- ==========================================

    EXEC dbo.SP_Pedidos_ConfirmarCheckout
        @IDUsuario = @IDUsuario,
        @IDReserva = @IDReserva,
        @IDDireccion = @IDDireccion,
        @ClaveIdempotencia = @Clave,
        @TotalEsperado = @TotalEsperado;

    -- ==========================================
    -- 9. SEGUNDA CONFIRMACION
    -- DEBE DEVOLVER EL MISMO PEDIDO
    -- ==========================================

    EXEC dbo.SP_Pedidos_ConfirmarCheckout
        @IDUsuario = @IDUsuario,
        @IDReserva = @IDReserva,
        @IDDireccion = @IDDireccion,
        @ClaveIdempotencia = @Clave,
        @TotalEsperado = @TotalEsperado;

    -- ==========================================
    -- 10. CONSULTAR PEDIDO CREADO
    -- ==========================================

    SELECT @IDPedido = IDPedido
    FROM dbo.Pedidos
    WHERE IDUsuario = @IDUsuario
      AND ClaveIdempotencia = @Clave;

    SELECT @FisicaPosterior = CantidadFisica
    FROM dbo.Existencias
    WHERE IDVariante = 4;

    -- ==========================================
    -- 11. VALIDAR QUE NO HAYA DUPLICADOS
    -- ==========================================

    IF (
        SELECT COUNT(*)
        FROM dbo.Pedidos
        WHERE IDUsuario = @IDUsuario
          AND ClaveIdempotencia = @Clave
    ) <> 1
        THROW 66104,
            'ERROR: pedido duplicado.', 1;

    IF (
        SELECT COUNT(*)
        FROM dbo.Pagos
        WHERE IDPedido = @IDPedido
    ) <> 1
        THROW 66105,
            'ERROR: pago duplicado o ausente.', 1;

    -- ==========================================
    -- 12. VALIDAR HISTORIAL
    -- ==========================================

    IF (
        SELECT COUNT(*)
        FROM dbo.HistorialEstadosPedido
        WHERE IDPedido = @IDPedido
    ) <> 1
        THROW 66106,
            'ERROR: historial ausente.', 1;

    -- ==========================================
    -- 13. VALIDAR INVENTARIO
    -- ==========================================

    IF @FisicaPosterior <>
       @FisicaAnterior - @Cantidad
        THROW 66107,
            'ERROR: descuento de inventario incorrecto.',
            1;

    -- ==========================================
    -- 14. VALIDAR KARDEX
    -- ==========================================

    IF (
        SELECT COUNT(*)
        FROM dbo.MovimientosInventario
        WHERE IDVariante = 4
          AND TipoMovimiento = 'SALIDA_VENTA'
          AND SaldoAnterior = @FisicaAnterior
          AND SaldoPosterior = @FisicaPosterior
          AND CantidadFirmada = -@Cantidad
    ) < 1
        THROW 66108,
            'ERROR: falta el movimiento en kardex.',
            1;

    -- ==========================================
    -- 15. VALIDAR RESERVA CONFIRMADA
    -- ==========================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.ReservasInventario
        WHERE IDReserva = @IDReserva
          AND Estado = 'CONFIRMADA'
    )
        THROW 66109,
            'ERROR: reserva no confirmada.', 1;

    -- ==========================================
    -- 16. VALIDAR CARRITO CONVERTIDO
    -- ==========================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Carritos
        WHERE IDCarrito = 11
          AND Estado = 'CONVERTIDO'
    )
        THROW 66110,
            'ERROR: carrito no convertido.', 1;

    -- ==========================================
    -- 17. RESULTADO DE LA PRUEBA
    -- ==========================================

    SELECT
        'OK: pedido y pago unicos; inventario, kardex y estados coherentes'
            AS Resultado,
        @IDPedido AS IDPedido,
        @IDReserva AS IDReserva,
        @FisicaAnterior AS ExistenciaAntes,
        @FisicaPosterior AS ExistenciaDurantePrueba,
        @TotalEsperado AS TotalPedido;

    -- ==========================================
    -- 18. REVERTIR CAMBIOS
    -- ==========================================

    ROLLBACK TRANSACTION;

    SELECT
        'ROLLBACK completado: no se conservaron los datos de la prueba.'
            AS Limpieza;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO
