
-- ==================================================
-- SHOPCART
-- PRUEBA: Rechazar inventario insuficiente
-- RF-03: Integridad del inventario
-- ==================================================

USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDVariante INT;
DECLARE @IDRol INT;
DECLARE @IDUsuario INT;
DECLARE @SaldoAntes INT;
DECLARE @SaldoDespues INT;
DECLARE @MovimientosAntes INT;
DECLARE @MovimientosDespues INT;
DECLARE @CodigoError INT = NULL;
DECLARE @MensajeError NVARCHAR(4000) = NULL;
DECLARE @CantidadSolicitada INT;

-- Evitar afectar una transaccion existente.
IF @@TRANCOUNT <> 0
    THROW 52010, 'Existe una transaccion abierta.', 1;

-- 1. Obtener variante
SELECT @IDVariante = IDVariante
FROM dbo.Variantes
WHERE SKU = N'BOT-500-NEG';

-- 2. Obtener rol
SELECT @IDRol = IDRol
FROM dbo.Roles
WHERE Nombre = 'Operador';

IF @IDVariante IS NULL OR @IDRol IS NULL
    THROW 52011, 'Faltan datos semilla.', 1;

-- 3. Consultar estado inicial
SELECT @SaldoAntes = CantidadFisica
FROM dbo.Existencias
WHERE IDVariante = @IDVariante;

IF @SaldoAntes IS NULL
    THROW 52012, 'No existe inventario.', 1;

IF @SaldoAntes = 2147483647
    THROW 52013, 'Utilice otra variante de prueba.', 1;

SELECT @MovimientosAntes = COUNT(*)
FROM dbo.MovimientosInventario
WHERE IDVariante = @IDVariante;

-- Intentar descontar una unidad
-- mas de las disponibles.
SET @CantidadSolicitada = @SaldoAntes + 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Usuario temporal de prueba
    INSERT INTO dbo.Usuarios (
        IDRol,
        Correo,
        PasswordHash,
        Activo
    )
    VALUES (
        @IDRol,
        CONCAT(
            N'qa-stock-',
            CONVERT(NVARCHAR(36), NEWID()),
            N'@example.invalid'
        ),
        N'QA_TRANSIENT_NO_LOGIN',
        1
    );

    SET @IDUsuario = SCOPE_IDENTITY();

    -- 4. Intentar movimiento invalido
    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = @IDVariante,
        @IDUsuario = @IDUsuario,
        @TipoMovimiento = 'AJUSTE_NEGATIVO',
        @Cantidad = @CantidadSolicitada,
        @Motivo = N'Prueba de stock insuficiente';

    -- Si no hubo error, revertimos igualmente.
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    SET @CodigoError = ERROR_NUMBER();
    SET @MensajeError = ERROR_MESSAGE();

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
END CATCH;

-- 5. Verificar que no hubo cambios
SELECT @SaldoDespues = CantidadFisica
FROM dbo.Existencias
WHERE IDVariante = @IDVariante;

SELECT @MovimientosDespues = COUNT(*)
FROM dbo.MovimientosInventario
WHERE IDVariante = @IDVariante;

-- 6. Resultado final
SELECT
    CASE
        WHEN @CodigoError = 51007
         AND @SaldoAntes = @SaldoDespues
         AND @MovimientosAntes = @MovimientosDespues
         AND NOT EXISTS (
             SELECT 1
             FROM dbo.Usuarios
             WHERE IDUsuario = @IDUsuario
         )
        THEN 'APROBADO'
        ELSE 'FALLO'
    END AS Resultado,
    @CodigoError AS CodigoError,
    @MensajeError AS Mensaje,
    @SaldoAntes AS SaldoAntes,
    @SaldoDespues AS SaldoDespues,
    @MovimientosDespues - @MovimientosAntes
        AS MovimientosAdicionales;
GO
