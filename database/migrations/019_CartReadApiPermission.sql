USE ShopCartDB;
GO

SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- Verificar que se aplico la migracion anterior
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 18
    )
        THROW 65410,
            'Primero ejecute la migracion 018.', 1;

    -- Evitar ejecutar la migracion dos veces
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 19
    )
    BEGIN

        -- Verificar que exista el Stored Procedure
        IF OBJECT_ID(
            N'dbo.SP_Carrito_ObtenerDetalle',
            N'P'
        ) IS NULL
            THROW 65411,
                'No existe el procedimiento del carrito.', 1;

        -- Conceder permiso de ejecucion a la API
        GRANT EXECUTE
        ON OBJECT::dbo.SP_Carrito_ObtenerDetalle
        TO [shopcart_api];

        -- Registrar migracion
        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            19,
            N'019_CartReadApiPermission'
        );

        PRINT 'Migracion 019 aplicada correctamente.';
    END
    ELSE
    BEGIN
        PRINT 'Migracion 019 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
