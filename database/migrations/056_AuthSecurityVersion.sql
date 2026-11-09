USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ==========================================
-- MIGRACION 056
-- VERSION DE SEGURIDAD PARA JWT
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 55
    )
        THROW 80000,
            'Primero ejecute la migracion 055.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 56
    )
    BEGIN

        IF COL_LENGTH(
            N'dbo.Usuarios',
            N'VersionSeguridad'
        ) IS NOT NULL
            THROW 80001,
                'La columna ya existe sin migracion.', 1;

        IF OBJECT_ID(
            N'dbo.SP_Auth_ObtenerPrincipalActual',
            N'P'
        ) IS NOT NULL
            THROW 80002,
                'El procedimiento ya existe.', 1;

        IF OBJECT_ID(
            N'dbo.TR_Usuarios_VersionSeguridad',
            N'TR'
        ) IS NOT NULL
            THROW 80003,
                'El trigger ya existe.', 1;

        -- ==================================
        -- 1. AGREGAR VERSION DE SEGURIDAD
        -- ==================================

        ALTER TABLE dbo.Usuarios
        ADD VersionSeguridad BIGINT NOT NULL
            CONSTRAINT DF_Usuarios_VersionSeguridad
            DEFAULT (1);

        -- ==================================
        -- 2. CONSULTAR PRINCIPAL ACTUAL
        -- ==================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Auth_ObtenerPrincipalActual
    @IDUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @IDUsuario IS NULL
       OR @IDUsuario <= 0
        RETURN;

    SELECT
        u.IDUsuario,
        r.Nombre AS NombreRol,
        u.VersionSeguridad
    FROM dbo.Usuarios AS u
    INNER JOIN dbo.Roles AS r
        ON r.IDRol = u.IDRol
    WHERE u.IDUsuario = @IDUsuario
      AND u.Activo = 1;
END;
';

        -- ==================================
        -- 3. INVALIDAR VERSIONES ANTERIORES
        -- ==================================

        EXEC sys.sp_executesql N'
CREATE TRIGGER dbo.TR_Usuarios_VersionSeguridad
ON dbo.Usuarios
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT (
        UPDATE(IDRol) OR UPDATE(Activo)
    )
        RETURN;

    UPDATE u
    SET VersionSeguridad =
        u.VersionSeguridad + CONVERT(BIGINT, 1)
    FROM dbo.Usuarios AS u
    INNER JOIN inserted AS i
        ON i.IDUsuario = u.IDUsuario
    INNER JOIN deleted AS d
        ON d.IDUsuario = u.IDUsuario
    WHERE i.IDRol <> d.IDRol
       OR i.Activo <> d.Activo;
END;
';

        -- ==================================
        -- 4. PERMISOS MINIMOS
        -- ==================================

        IF DATABASE_PRINCIPAL_ID(
            N'shopcart_api'
        ) IS NULL
            THROW 80004,
                'No existe shopcart_api.', 1;

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Auth_ObtenerPrincipalActual
        TO [shopcart_api];

        -- ==================================
        -- 5. REGISTRAR MIGRACION
        -- ==================================

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            56,
            N'056_AuthSecurityVersion'
        );

        PRINT 'OK: Migracion 056 aplicada.';
    END
    ELSE
    BEGIN

        IF COL_LENGTH(
            N'dbo.Usuarios',
            N'VersionSeguridad'
        ) IS NULL
           OR OBJECT_ID(
                N'dbo.SP_Auth_ObtenerPrincipalActual',
                N'P'
           ) IS NULL
           OR OBJECT_ID(
                N'dbo.TR_Usuarios_VersionSeguridad',
                N'TR'
           ) IS NULL
            THROW 80005,
                'Migracion incompleta.', 1;

        PRINT 'OK: Migracion 056 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO
