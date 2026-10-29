
USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- Validar dependencia
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 12
    )
        THROW 65012,
            'Primero debe ejecutar la migracion 012.', 1;

    -- Evitar aplicar dos veces la migracion
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 13
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Auth_ObtenerUsuarioPorCorreo', N'P'
        ) IS NOT NULL
            THROW 65013,
                'El procedimiento ya existe sin migracion registrada.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Auth_ObtenerUsuarioPorCorreo
    @Correo NVARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Correo IS NULL
       OR LEN(LTRIM(RTRIM(@Correo))) = 0
        THROW 65014, ''Correo obligatorio.'', 1;

    SELECT
        u.IDUsuario,
        u.Correo,
        u.PasswordHash,
        u.IDRol,
        r.Nombre AS NombreRol
    FROM dbo.Usuarios AS u
    INNER JOIN dbo.Roles AS r
        ON r.IDRol = u.IDRol
    WHERE u.Correo = LTRIM(RTRIM(@Correo))
      AND u.Activo = 1;
END;
';

        -- El backend solo puede ejecutar el SP
        IF DATABASE_PRINCIPAL_ID(
            N'shopcart_api'
        ) IS NULL
            THROW 65015,
                'No existe el usuario shopcart_api.', 1;

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Auth_ObtenerUsuarioPorCorreo
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            13,
            N'013_AuthUserLookupProcedure'
        );

        PRINT 'Migracion 013 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Auth_ObtenerUsuarioPorCorreo', N'P'
        ) IS NULL
            THROW 65016,
                'Migracion registrada pero falta el procedimiento.', 1;

        PRINT 'Migracion 013 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
