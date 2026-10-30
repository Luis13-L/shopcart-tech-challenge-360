USE ShopCartDB;
GO

SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 21
    )
        THROW 65520,
            'Primero ejecute la migracion 021.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 22
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Carrito_EliminarProducto', N'P'
        ) IS NULL
            THROW 65521,
                'No existe el procedimiento de eliminacion.', 1;

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Carrito_EliminarProducto
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            22,
            N'022_CartDeleteApiPermission'
        );

        PRINT 'Migracion 022 aplicada correctamente.';
    END
    ELSE
        PRINT 'Migracion 022 ya aplicada.';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
