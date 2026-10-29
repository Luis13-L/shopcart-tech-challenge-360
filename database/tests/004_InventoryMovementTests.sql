
-- ==================================================
-- PROYECTO: ShopCart
-- PRUEBA: Movimiento positivo de inventario
-- OBJETIVO: Verificar saldo y kardex
-- ==================================================

USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDRol INT;
DECLARE @IDUsuario INT;
DECLARE @IDVariante INT;
DECLARE @SaldoInicial INT;
DECLARE @SaldoFinal INT;
DECLARE @MovimientosIniciales INT;
DECLARE @MovimientosFinales INT;

-- ==========================================
-- 1. OBTENER DATOS DE PRUEBA
-- ==========================================

SELECT @IDRol = IDRol
FROM dbo.Roles
WHERE Nombre = 'Operador';

SELECT @IDVariante = IDVariante
FROM dbo.Variantes
WHERE SKU = N'BOT-500-NEG';

IF @IDRol IS NULL OR @IDVariante IS NULL
    THROW 52001, 'Faltan datos semilla.', 1;

SELECT @SaldoInicial = CantidadFisica
FROM dbo.Existencias
WHERE IDVariante = @IDVariante;

IF @SaldoInicial IS NULL
    THROW 52002, 'La variante no tiene existencia.', 1;

SELECT @MovimientosIniciales = COUNT(*)
FROM dbo.MovimientosInventario
WHERE IDVariante = @IDVariante;

BEGIN TRY
    -- ======================================
    -- 2. INICIAR TRANSACCION DE PRUEBA
    -- ======================================
    BEGIN TRANSACTION;

    -- Usuario temporal exclusivo de QA.
    -- No tiene contraseña utilizable y
    -- se elimina mediante ROLLBACK.
    INSERT INTO dbo.Usuarios (
        IDRol,
        Correo,
        PasswordHash,
        Activo
    )
    VALUES (
        @IDRol,
        CONCAT(
            N'qa-',
            CONVERT(NVARCHAR(36), NEWID()),
            N'@example.invalid'
        ),
        N'QA_TRANSIENT_NO_LOGIN',
        1
    );

    SET @IDUsuario = SCOPE_IDENTITY();

    -- ======================================
    -- 3. EJECUTAR STORED PROCEDURE
    -- ======================================
    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = @IDVariante,
        @IDUsuario = @IDUsuario,
        @TipoMovimiento = 'ENTRADA',
        @Cantidad = 10,
        @Motivo = N'Prueba transaccional de entrada';

    -- ======================================
    -- 4. CONSULTAR RESULTADOS
    -- ======================================
    SELECT @SaldoFinal = CantidadFisica
    FROM dbo.Existencias
    WHERE IDVariante = @IDVariante;

    SELECT @MovimientosFinales = COUNT(*)
    FROM dbo.MovimientosInventario
    WHERE IDVariante = @IDVariante;

    -- ======================================
    -- 5. VERIFICAR RESULTADOS
    -- ======================================
    IF @SaldoFinal <> @SaldoInicial + 10
        THROW 52003, 'El saldo no aumento 10 unidades.', 1;

    IF @MovimientosFinales <> @MovimientosIniciales + 1
        THROW 52004, 'No se registro exactamente un movimiento.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.MovimientosInventario
        WHERE IDVariante = @IDVariante
          AND IDUsuario = @IDUsuario
          AND TipoMovimiento = 'ENTRADA'
          AND CantidadFirmada = 10
          AND SaldoAnterior = @SaldoInicial
          AND SaldoPosterior = @SaldoFinal
    )
        THROW 52005, 'Movimiento de kardex inconsistente.', 1;

    SELECT
        'APROBADO' AS Resultado,
        @SaldoInicial AS SaldoInicial,
        @SaldoFinal AS SaldoFinal,
        @MovimientosFinales - @MovimientosIniciales
            AS MovimientosRegistrados;

    -- ======================================
    -- 6. REVERTIR DATOS TEMPORALES
    -- ======================================
    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

-- ==========================================
-- 7. VERIFICAR QUE EL ROLLBACK FUNCIONO
-- ==========================================
SELECT
    @SaldoInicial AS SaldoAntesPrueba,
    CantidadFisica AS SaldoDespuesRollback,
    CASE
        WHEN CantidadFisica = @SaldoInicial
        THEN 'APROBADO'
        ELSE 'FALLO'
    END AS ResultadoRollback
FROM dbo.Existencias
WHERE IDVariante = @IDVariante;
GO
