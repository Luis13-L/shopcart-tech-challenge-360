USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDAdmin INT;
DECLARE @IDVariante INT = 4;

DECLARE @SaldoInicial INT;
DECLARE @SaldoActual INT;
DECLARE @IDMovimiento BIGINT;

DECLARE @Motivo NVARCHAR(300) = CONCAT(
    N'TEST AUDITORIA INVENTARIO ',
    CONVERT(NVARCHAR(36), NEWID())
);

-- ==========================================
-- 1. VALIDAR PRECONDICIONES
-- ==========================================

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 38
)
    THROW 73501,
        'Primero ejecute la migracion 038.',
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
    THROW 73502,
        'No existe Administrador activo.',
        1;

SELECT
    @SaldoInicial = CantidadFisica
FROM dbo.Existencias
WHERE IDVariante = @IDVariante;

IF @SaldoInicial IS NULL
    THROW 73503,
        'No existe la variante de prueba.',
        1;

IF @SaldoInicial = 2147483647
    THROW 73504,
        'No hay margen para una entrada de prueba.',
        1;

-- ==========================================
-- 2. PRUEBA TRANSACCIONAL
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = @IDVariante,
        @IDUsuario = @IDAdmin,
        @TipoMovimiento = 'ENTRADA',
        @Cantidad = 1,
        @Motivo = @Motivo;

    -- ======================================
    -- 3. VERIFICAR INVENTARIO
    -- ======================================

    SELECT @SaldoActual = CantidadFisica
    FROM dbo.Existencias
    WHERE IDVariante = @IDVariante;

    IF @SaldoActual <> @SaldoInicial + 1
        THROW 73505,
            'El inventario no aumento correctamente.',
            1;

    -- ======================================
    -- 4. LOCALIZAR MOVIMIENTO DE KARDEX
    -- ======================================

    SELECT TOP (1)
        @IDMovimiento = IDMovimientoInventario
    FROM dbo.MovimientosInventario
    WHERE IDVariante = @IDVariante
      AND IDUsuario = @IDAdmin
      AND Motivo = @Motivo
    ORDER BY IDMovimientoInventario DESC;

    IF @IDMovimiento IS NULL
        THROW 73506,
            'No se genero el movimiento de kardex.',
            1;

    -- ======================================
    -- 5. VERIFICAR BITACORA
    -- ======================================

    IF (
        SELECT COUNT(*)
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'INVENTARIO'
          AND Entidad = 'Existencias'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDVariante)
          AND IDUsuario = @IDAdmin
          AND Accion = 'AJUSTAR'
          AND JSON_VALUE(
              ValoresNuevos,
              '$.motivo'
          ) = @Motivo
    ) <> 1
        THROW 73507,
            'No se genero una auditoria unica.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'INVENTARIO'
          AND JSON_VALUE(
              ValoresAnteriores,
              '$.cantidadFisica'
          ) = CONVERT(
              NVARCHAR(30), @SaldoInicial
          )
          AND JSON_VALUE(
              ValoresNuevos,
              '$.cantidadFisica'
          ) = CONVERT(
              NVARCHAR(30), @SaldoInicial + 1
          )
          AND JSON_VALUE(
              ValoresNuevos,
              '$.tipoMovimiento'
          ) = 'ENTRADA'
          AND JSON_VALUE(
              ValoresNuevos,
              '$.idMovimientoInventario'
          ) = CONVERT(
              NVARCHAR(30), @IDMovimiento
          )
    )
        THROW 73508,
            'La auditoria contiene valores incorrectos.',
            1;

    -- ======================================
    -- 6. MOSTRAR RESULTADOS
    -- ======================================

    SELECT
        IDBitacora,
        IDUsuario,
        Modulo,
        Entidad,
        IDEntidad,
        Accion,
        ValoresAnteriores,
        ValoresNuevos
    FROM dbo.BitacoraAuditoria
    WHERE JSON_VALUE(
        ValoresNuevos,
        '$.motivo'
    ) = @Motivo;

    SELECT
        @SaldoInicial AS ExistenciaInicial,
        @SaldoActual AS ExistenciaDurantePrueba,
        'OK: auditoria automatica de inventario'
            AS Resultado;

    -- ======================================
    -- 7. REVERTIR DATOS DE PRUEBA
    -- ======================================

    ROLLBACK TRANSACTION;

    -- Comprobar que todo fue revertido.
    IF EXISTS (
        SELECT 1
        FROM dbo.MovimientosInventario
        WHERE Motivo = @Motivo
    )
        THROW 73509,
            'El kardex de prueba no se revirtio.',
            1;

    IF EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE JSON_VALUE(
            ValoresNuevos,
            '$.motivo'
        ) = @Motivo
    )
        THROW 73510,
            'La auditoria de prueba no se revirtio.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Existencias
        WHERE IDVariante = @IDVariante
          AND CantidadFisica = @SaldoInicial
    )
        THROW 73511,
            'La existencia no fue restaurada.',
            1;

    SELECT
        'OK: kardex, auditoria y existencias revertidos'
            AS ResultadoFinal;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
