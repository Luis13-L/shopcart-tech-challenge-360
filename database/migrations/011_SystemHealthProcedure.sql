
-- ===============================================
-- SHOPCART - MIGRACION 011
-- Procedimiento de verificacion de conexion
-- ===============================================

USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 10
    )
        THROW 64001,
            'Debe ejecutar primero la migracion 010.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 11
    )
    BEGIN
        IF SUSER_ID(N'shopcart_api') IS NULL
            THROW 64002,
                'No existe el login shopcart_api.',
                1;

        IF OBJECT_ID(
            N'dbo.SP_Sistema_VerificarConexion', N'P'
        ) IS NOT NULL
            THROW 64003,
                'Procedimiento existente sin migracion.',
                1;

        -- Crear usuario de BD si no existe
        IF DATABASE_PRINCIPAL_ID(N'shopcart_api') IS NULL
        BEGIN
            CREATE USER [shopcart_api]
            FOR LOGIN [shopcart_api];
        END;

        -- Crear Stored Procedure
        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Sistema_VerificarConexion
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        CAST(1 AS INT) AS Disponible,
        SYSUTCDATETIME() AS FechaServidorUTC;
END;
';

        -- Permiso especifico al procedimiento
        GRANT EXECUTE
        ON OBJECT::dbo.SP_Sistema_VerificarConexion
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            11,
            N'011_SystemHealthProcedure'
        );
    END
    ELSE IF OBJECT_ID(
        N'dbo.SP_Sistema_VerificarConexion', N'P'
    ) IS NULL
        THROW 64004,
            'Migracion registrada sin procedimiento.',
            1;

    COMMIT TRANSACTION;

    PRINT 'Migracion 011 verificada.';

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
