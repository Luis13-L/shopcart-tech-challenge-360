USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDAdmin INT;
DECLARE @IDPedido BIGINT;

DECLARE @Marca NVARCHAR(300) =
    CONCAT(
        N'TEST AUDITORIA PEDIDOS ',
        CONVERT(NVARCHAR(36), NEWID())
    );

-- ==========================================
-- 1. PRECONDICIONES
-- ==========================================

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 37
)
    THROW 73301,
        'Primero ejecute la migracion 037.',
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
    THROW 73302,
        'No existe Administrador activo.',
        1;

-- Preferimos el pedido 6;
-- de lo contrario seleccionamos otro.
SELECT TOP (1)
    @IDPedido = IDPedido
FROM dbo.Pedidos
ORDER BY
    CASE WHEN IDPedido = 6 THEN 0 ELSE 1 END,
    IDPedido DESC;

IF @IDPedido IS NULL
    THROW 73303,
        'No hay pedidos para ejecutar la prueba.',
        1;

-- ==========================================
-- 2. TRANSACCION DE PRUEBA
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    -- Este es un evento ficticio de historial,
    -- NO una modificacion del pedido real.
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
        @IDAdmin,
        'PAGADO',
        'PREPARANDO',
        @Marca,
        SYSUTCDATETIME()
    );

    -- ======================================
    -- 3. VERIFICAR AUDITORIA AUTOMATICA
    -- ======================================

    IF (
        SELECT COUNT(*)
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'PEDIDOS'
          AND Entidad = 'Pedidos'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDPedido)
          AND Accion = 'CAMBIAR_ESTADO'
          AND JSON_VALUE(
              ValoresNuevos,
              '$.observacion'
          ) = @Marca
    ) <> 1
        THROW 73304,
            'El trigger no genero una auditoria unica.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'PEDIDOS'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDPedido)
          AND JSON_VALUE(
              ValoresAnteriores,
              '$.estado'
          ) = 'PAGADO'
          AND JSON_VALUE(
              ValoresNuevos,
              '$.estado'
          ) = 'PREPARANDO'
          AND JSON_VALUE(
              ValoresNuevos,
              '$.observacion'
          ) = @Marca
    )
        THROW 73305,
            'Los valores de auditoria son incorrectos.',
            1;

    SELECT
        IDBitacora,
        IDUsuario,
        Modulo,
        Entidad,
        IDEntidad,
        Accion,
        ValoresAnteriores,
        ValoresNuevos,
        FechaRegistro
    FROM dbo.BitacoraAuditoria
    WHERE JSON_VALUE(
        ValoresNuevos,
        '$.observacion'
    ) = @Marca;

    PRINT
        'OK: trigger registra cambios de estado.';

    -- ======================================
    -- 4. REVERTIR TODO
    -- ======================================

    ROLLBACK TRANSACTION;

    -- ======================================
    -- 5. VALIDAR QUE EL ROLLBACK
    -- TAMBIEN REVIERTE LA AUDITORIA
    -- ======================================

    IF EXISTS (
        SELECT 1
        FROM dbo.HistorialEstadosPedido
        WHERE Observacion = @Marca
    )
        THROW 73306,
            'El historial de prueba no se revirtio.',
            1;

    IF EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE JSON_VALUE(
            ValoresNuevos,
            '$.observacion'
        ) = @Marca
    )
        THROW 73307,
            'La auditoria no se revirtio.',
            1;

    SELECT
        'OK: auditoria automatica validada'
            AS Resultado,
        'OK: ROLLBACK de historial y auditoria'
            AS Integridad;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
