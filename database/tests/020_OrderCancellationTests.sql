USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDPedido BIGINT;
DECLARE @IDAdministrador INT;
DECLARE @EstadoOriginal VARCHAR(20);
DECLARE @HistorialAntes BIGINT;
DECLARE @MovimientosAntes BIGINT;
DECLARE @NumeroLineas INT;

-- Seleccionar un pedido cancelable.
SELECT TOP (1)
    @IDPedido = IDPedido,
    @EstadoOriginal = Estado
FROM dbo.Pedidos
WHERE Estado IN ('PAGADO', 'PREPARANDO')
ORDER BY IDPedido DESC;

SELECT TOP (1)
    @IDAdministrador = u.IDUsuario
FROM dbo.Usuarios u
JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Administrador'
  AND u.Activo = 1
ORDER BY u.IDUsuario;

IF @IDPedido IS NULL
    THROW 68100,
        'No existe un pedido cancelable.', 1;

IF @IDAdministrador IS NULL
    THROW 68101,
        'No existe un administrador activo.', 1;

SELECT @HistorialAntes = COUNT_BIG(*)
FROM dbo.HistorialEstadosPedido
WHERE IDPedido = @IDPedido;

SELECT @NumeroLineas = COUNT(*)
FROM dbo.DetallesPedido
WHERE IDPedido = @IDPedido;

IF @NumeroLineas = 0
    THROW 68102,
        'El pedido no tiene detalles.', 1;

-- Capturar el inventario inicial.
CREATE TABLE #StockAntes (
    IDVariante INT NOT NULL PRIMARY KEY,
    CantidadAntes INT NOT NULL,
    CantidadPedido INT NOT NULL
);

INSERT INTO #StockAntes (
    IDVariante,
    CantidadAntes,
    CantidadPedido
)
SELECT
    d.IDVariante,
    e.CantidadFisica,
    d.Cantidad
FROM dbo.DetallesPedido d
JOIN dbo.Existencias e
    ON e.IDVariante = d.IDVariante
WHERE d.IDPedido = @IDPedido;

IF (
    SELECT COUNT(*) FROM #StockAntes
) <> @NumeroLineas
    THROW 68103,
        'Faltan existencias para alguna variante.', 1;

DECLARE @MotivoKardex NVARCHAR(300) = CONCAT(
    N'Cancelacion pedido ',
    @IDPedido,
    N': ',
    N'Prueba de cancelacion SQL'
);

SELECT @MovimientosAntes = COUNT_BIG(*)
FROM dbo.MovimientosInventario
WHERE TipoMovimiento = 'DEVOLUCION'
  AND Motivo = @MotivoKardex;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Primera cancelacion.
    EXEC dbo.SP_Pedidos_CancelarPedido
        @IDPedido = @IDPedido,
        @IDUsuario = @IDAdministrador,
        @Motivo = N'Prueba de cancelacion SQL';

    -- Segunda solicitud: no debe duplicar
    -- los movimientos de inventario.
    EXEC dbo.SP_Pedidos_CancelarPedido
        @IDPedido = @IDPedido,
        @IDUsuario = @IDAdministrador,
        @Motivo = N'Prueba de cancelacion SQL';

    -- Validar estado.
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pedidos
        WHERE IDPedido = @IDPedido
          AND Estado = 'CANCELADO'
    )
        THROW 68104,
            'El pedido no fue cancelado.', 1;

    -- Validar pago simulado.
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pagos
        WHERE IDPedido = @IDPedido
          AND Estado = 'REEMBOLSADO'
    )
        THROW 68105,
            'El pago no fue revertido.', 1;

    -- Validar inventario.
    IF EXISTS (
        SELECT 1
        FROM #StockAntes a
        JOIN dbo.Existencias e
            ON e.IDVariante = a.IDVariante
        WHERE CONVERT(BIGINT, e.CantidadFisica)
            <> CONVERT(BIGINT, a.CantidadAntes)
             + CONVERT(BIGINT, a.CantidadPedido)
    )
        THROW 68106,
            'El inventario fue reintegrado incorrectamente.',
            1;

    -- Un unico cambio de estado.
    IF (
        SELECT COUNT_BIG(*)
        FROM dbo.HistorialEstadosPedido
        WHERE IDPedido = @IDPedido
    ) <> @HistorialAntes + 1
        THROW 68107,
            'El historial esta duplicado.', 1;

    -- Un movimiento de devolucion por linea.
    IF (
        SELECT COUNT_BIG(*)
        FROM dbo.MovimientosInventario
        WHERE TipoMovimiento = 'DEVOLUCION'
          AND Motivo = @MotivoKardex
    ) <> @MovimientosAntes + @NumeroLineas
        THROW 68108,
            'Cantidad incorrecta de movimientos.',
            1;

    SELECT
        'OK: cancelacion e idempotencia correctas'
        AS Resultado,
        @IDPedido AS IDPedido;

    SELECT
        a.IDVariante,
        a.CantidadAntes,
        a.CantidadPedido,
        e.CantidadFisica AS CantidadDespues
    FROM #StockAntes a
    JOIN dbo.Existencias e
        ON e.IDVariante = a.IDVariante;

    -- Deshacer todas las operaciones.
    ROLLBACK TRANSACTION;

    SELECT
        Estado
    FROM dbo.Pedidos
    WHERE IDPedido = @IDPedido;

    SELECT
        'OK: ROLLBACK completado'
        AS Limpieza;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
