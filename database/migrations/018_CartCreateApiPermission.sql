
USE ShopCartDB;
GO

SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 17
    )
        THROW 65400,
            'Primero ejecute la migracion 017.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 18
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Carrito_Crear', N'P'
        ) IS NULL
            THROW 65401,
                'No existe SP_Carrito_Crear.', 1;

        IF DATABASE_PRINCIPAL_ID(
            N'shopcart_api'
        ) IS NULL
            THROW 65402,
                'No existe shopcart_api.', 1;

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Carrito_Crear
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            18,
            N'018_CartCreateApiPermission'
        );

        PRINT 'Migracion 018 aplicada.';
    END
    ELSE
        PRINT 'Migracion 018 ya aplicada.';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

