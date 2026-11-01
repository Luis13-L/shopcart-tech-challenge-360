USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDAdmin INT;
DECLARE @IDCupon INT;

DECLARE @Codigo VARCHAR(50) = CONCAT(
    'AUDTEST_',
    REPLACE(
        CONVERT(VARCHAR(36), NEWID()),
        '-', ''
    )
);

-- Obtener Administrador
SELECT TOP (1)
    @IDAdmin = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Administrador'
  AND u.Activo = 1
ORDER BY u.IDUsuario;

IF @IDAdmin IS NULL
    THROW 73701,
        'No existe Administrador activo.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Crear cupon temporal
    EXEC dbo.SP_Cupones_Crear
        @IDUsuario = @IDAdmin,
        @Codigo = @Codigo,
        @TipoDescuento = 'PORCENTAJE',
        @Valor = 10.00,
        @MontoMinimo = 100.00,
        @LimiteUsos = 10,
        @LimitePorCliente = 1,
        @FechaInicio = '2026-10-01',
        @FechaFin = '2026-12-31',
        @Activo = 1;

    SELECT @IDCupon = IDCupon
    FROM dbo.Cupones
    WHERE Codigo = @Codigo;

    IF @IDCupon IS NULL
        THROW 73702,
            'No se creo el cupon.', 1;

    -- Verificar auditoria CREAR
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CUPONES'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDCupon)
          AND Accion = 'CREAR'
          AND IDUsuario = @IDAdmin
    )
        THROW 73703,
            'No se registro auditoria CREAR.', 1;

    -- Desactivar cupon
    EXEC dbo.SP_Cupones_CambiarEstado
        @IDUsuario = @IDAdmin,
        @IDCupon = @IDCupon,
        @Activo = 0;

    -- Verificar auditoria DESACTIVAR
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CUPONES'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDCupon)
          AND Accion = 'DESACTIVAR'
          AND JSON_VALUE(
              ValoresAnteriores, '$.activo'
          ) = 'true'
          AND JSON_VALUE(
              ValoresNuevos, '$.activo'
          ) = 'false'
    )
        THROW 73704,
            'No se registro auditoria DESACTIVAR.', 1;

    -- Mostrar evidencia
    SELECT
        IDBitacora,
        IDUsuario,
        Modulo,
        IDEntidad,
        Accion,
        ValoresAnteriores,
        ValoresNuevos
    FROM dbo.BitacoraAuditoria
    WHERE Modulo = 'CUPONES'
      AND IDEntidad =
          CONVERT(VARCHAR(40), @IDCupon)
    ORDER BY IDBitacora;

    SELECT
        'OK: auditoria de cupones correcta'
            AS Resultado;

    -- Revertir cupon y auditoria
    ROLLBACK TRANSACTION;

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
