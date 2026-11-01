USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @IDAdmin INT;
DECLARE @IDBitacora BIGINT;
DECLARE @Marcador VARCHAR(40);

CREATE TABLE #Resultados (
    Prueba VARCHAR(30),
    Resultado VARCHAR(100)
);

SELECT TOP (1)
    @IDAdmin = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Administrador'
  AND u.Activo = 1
ORDER BY u.IDUsuario;

IF @IDAdmin IS NULL
    THROW 73801,
        'No existe administrador activo.', 1;

-- ==========================================
-- PRUEBA 1: BLOQUEAR UPDATE
-- ==========================================

SET @Marcador =
    CONVERT(VARCHAR(36), NEWID());

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC dbo.SP_Auditoria_RegistrarCambio
        @IDUsuario = @IDAdmin,
        @Modulo = 'CATALOGO',
        @Entidad = 'Productos',
        @IDEntidad = @Marcador,
        @Accion = 'ACTUALIZAR',
        @ValoresAnteriores = N'{"precio":150}',
        @ValoresNuevos = N'{"precio":175}';

    SELECT @IDBitacora = IDBitacora
    FROM dbo.BitacoraAuditoria
    WHERE IDEntidad = @Marcador;

    IF @IDBitacora IS NULL
        THROW 73802,
            'No se genero la auditoria.', 1;

    -- Esta operacion DEBE ser rechazada.
    UPDATE dbo.BitacoraAuditoria
    SET Entidad = 'Modificado'
    WHERE IDBitacora = @IDBitacora;

    ROLLBACK TRANSACTION;

    THROW 73803,
        'ERROR: UPDATE fue permitido.', 1;

END TRY
BEGIN CATCH
    DECLARE @ErrorUpdate INT = ERROR_NUMBER();

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF @ErrorUpdate <> 73030
        THROW;

    INSERT INTO #Resultados
    VALUES (
        'UPDATE',
        'OK: modificacion bloqueada'
    );
END CATCH;

-- ==========================================
-- PRUEBA 2: BLOQUEAR DELETE
-- ==========================================

SET @Marcador =
    CONVERT(VARCHAR(36), NEWID());

SET @IDBitacora = NULL;

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC dbo.SP_Auditoria_RegistrarCambio
        @IDUsuario = @IDAdmin,
        @Modulo = 'CUPONES',
        @Entidad = 'Cupones',
        @IDEntidad = @Marcador,
        @Accion = 'CREAR',
        @ValoresAnteriores = NULL,
        @ValoresNuevos = N'{"codigo":"TEST"}';

    SELECT @IDBitacora = IDBitacora
    FROM dbo.BitacoraAuditoria
    WHERE IDEntidad = @Marcador;

    IF @IDBitacora IS NULL
        THROW 73804,
            'No se genero la auditoria.', 1;

    -- Esta operacion DEBE ser rechazada.
    DELETE FROM dbo.BitacoraAuditoria
    WHERE IDBitacora = @IDBitacora;

    ROLLBACK TRANSACTION;

    THROW 73805,
        'ERROR: DELETE fue permitido.', 1;

END TRY
BEGIN CATCH
    DECLARE @ErrorDelete INT = ERROR_NUMBER();

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF @ErrorDelete <> 73030
        THROW;

    INSERT INTO #Resultados
    VALUES (
        'DELETE',
        'OK: eliminacion bloqueada'
    );
END CATCH;

-- ==========================================
-- RESULTADOS
-- ==========================================

SELECT Prueba, Resultado
FROM #Resultados;

DROP TABLE #Resultados;

PRINT 'OK: pruebas de inmutabilidad finalizadas.';
GO
