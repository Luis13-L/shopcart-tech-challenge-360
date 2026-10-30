USE ShopCartDB;
GO

SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 20
    )
        THROW 65510,
            'Primero ejecute la migracion 020.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 21
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Carrito_GuardarDetalle',
            N'P'
        ) IS NULL
            THROW 65511,
                'No existe SP_Carrito_GuardarDetalle.', 1;

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Carrito_GuardarDetalle
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            21,
            N'021_CartSaveApiPermission'
        );

        PRINT 'Migracion 021 aplicada correctamente.';
    END
    ELSE
        PRINT 'Migracion 021 ya aplicada.';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
