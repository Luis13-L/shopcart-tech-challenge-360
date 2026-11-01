USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ==========================================
-- TEST 019: TRANSICIONES DE PEDIDOS
-- Los cambios se revierten con ROLLBACK.
-- Ejecutar en base de desarrollo.
-- ==========================================

DECLARE @IDPedido BIGINT;
DECLARE @IDOperador INT;
DECLARE @HistorialAnterior BIGINT;

-- Obtener un pedido PAGADO.
SELECT TOP (1)
    @IDPedido = IDPedido
FROM dbo.Pedidos
WHERE Estado = 'PAGADO'
ORDER BY IDPedido DESC;

-- Obtener un administrador activo.
SELECT TOP (1)
    @IDOperador = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Administrador'
  AND u.Activo = 1
ORDER BY u.IDUsuario;

IF @IDPedido IS NULL
    THROW 67101,
        'No existe un pedido PAGADO para probar.',
        1;

IF @IDOperador IS NULL
    THROW 67102,
        'No existe un administrador activo.',
        1;

SELECT @HistorialAnterior = COUNT_BIG(*)
FROM dbo.HistorialEstadosPedido
WHERE IDPedido = @IDPedido;

BEGIN TRY
    BEGIN TRANSACTION;

    -- PASO 1: PAGADO -> PREPARANDO
    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @IDPedido,
        @IDUsuario = @IDOperador,
        @EstadoNuevo = 'PREPARANDO',
        @Observacion = N'Prueba: preparar pedido';

    -- PASO 2: PREPARANDO -> DESPACHADO
    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @IDPedido,
        @IDUsuario = @IDOperador,
        @EstadoNuevo = 'DESPACHADO',
        @Observacion = N'Prueba: despachar pedido';

    -- PASO 3: DESPACHADO -> ENTREGADO
    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @IDPedido,
        @IDUsuario = @IDOperador,
        @EstadoNuevo = 'ENTREGADO',
        @Observacion = N'Prueba: entregar pedido';

    -- Validar estado final.
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pedidos
        WHERE IDPedido = @IDPedido
          AND Estado = 'ENTREGADO'
    )
        THROW 67103,
            'ERROR: Estado final incorrecto.',
            1;

    -- Validar tres movimientos de historial.
    IF (
        SELECT COUNT_BIG(*)
        FROM dbo.HistorialEstadosPedido
        WHERE IDPedido = @IDPedido
    ) <> @HistorialAnterior + 3
        THROW 67104,
            'ERROR: Historial incompleto.',
            1;

    -- Consultar los resultados.
    SELECT
        IDPedido,
        Estado,
        FechaActualizacion
    FROM dbo.Pedidos
    WHERE IDPedido = @IDPedido;

    SELECT TOP (3)
        EstadoAnterior,
        EstadoNuevo,
        IDUsuario,
        FechaCambio
    FROM dbo.HistorialEstadosPedido
    WHERE IDPedido = @IDPedido
    ORDER BY IDHistorialPedido DESC;

    SELECT
        'OK: transiciones e historial correctos'
        AS Resultado;

    -- No conservar cambios.
    ROLLBACK TRANSACTION;

    -- Verificar que regresamos a PAGADO.
    SELECT
        IDPedido,
        Estado
    FROM dbo.Pedidos
    WHERE IDPedido = @IDPedido;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

-- ==========================================
-- PRUEBA NEGATIVA:
-- PAGADO -> ENTREGADO
-- Debe devolver error 67014.
-- ==========================================

DECLARE @IDPedidoNegativo BIGINT;
DECLARE @IDAdminNegativo INT;

SELECT TOP (1)
    @IDPedidoNegativo = IDPedido
FROM dbo.Pedidos
WHERE Estado = 'PAGADO'
ORDER BY IDPedido DESC;

SELECT TOP (1)
    @IDAdminNegativo = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Administrador'
  AND u.Activo = 1
ORDER BY u.IDUsuario;

IF @IDPedidoNegativo IS NULL
   OR @IDAdminNegativo IS NULL
    THROW 67105,
        'Faltan datos para la prueba negativa.',
        1;

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @IDPedidoNegativo,
        @IDUsuario = @IDAdminNegativo,
        @EstadoNuevo = 'ENTREGADO',
        @Observacion = N'Prueba de transicion invalida';

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    SELECT
        'ERROR: se permitio una transicion invalida'
        AS Resultado;

END TRY
BEGIN CATCH
    DECLARE @NumeroError INT = ERROR_NUMBER();
    DECLARE @MensajeError NVARCHAR(4000) =
        ERROR_MESSAGE();

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    SELECT
        @NumeroError AS CodigoError,
        @MensajeError AS MensajeError,
        CASE
            WHEN @NumeroError = 67014
                THEN 'OK'
            ELSE 'REVISAR'
        END AS Resultado;
END CATCH;
GO
