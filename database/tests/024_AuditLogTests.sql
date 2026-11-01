
USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDAdmin INT;
DECLARE @IDEntidad VARCHAR(40) =
    CONVERT(VARCHAR(36), NEWID());

SELECT TOP (1)
    @IDAdmin = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Administrador'
  AND u.Activo = 1
ORDER BY u.IDUsuario;

IF @IDAdmin IS NULL
    THROW 73101,
        'No existe Administrador activo.',
        1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Registrar un cambio de ejemplo.
    EXEC dbo.SP_Auditoria_RegistrarCambio
        @IDUsuario = @IDAdmin,
        @Modulo = 'CUPONES',
        @Entidad = 'Cupones',
        @IDEntidad = @IDEntidad,
        @Accion = 'ACTUALIZAR',
        @ValoresAnteriores = N'{"valor":15.00}',
        @ValoresNuevos = N'{"valor":20.00}';

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE IDEntidad = @IDEntidad
          AND IDUsuario = @IDAdmin
          AND Modulo = 'CUPONES'
          AND Accion = 'ACTUALIZAR'
          AND JSON_VALUE(
              ValoresAnteriores,
              '$.valor'
          ) = '15.00'
          AND JSON_VALUE(
              ValoresNuevos,
              '$.valor'
          ) = '20.00'
    )
        THROW 73102,
            'La auditoria no se registro correctamente.',
            1;

    PRINT 'OK: registro de auditoria correcto.';

    -- Consultar como Administrador.
    EXEC dbo.SP_Auditoria_Listar
        @IDUsuario = @IDAdmin,
        @Modulo = 'CUPONES',
        @Pagina = 1,
        @TamanoPagina = 10;

    PRINT 'OK: consulta administrativa correcta.';

    ROLLBACK TRANSACTION;

    PRINT 'OK: ROLLBACK completado.';

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
