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
        WHERE Numero = 44
    )
        THROW 78001,
            'Primero ejecute la migracion 044.', 1;

    IF OBJECT_ID(N'dbo.Existencias', N'U') IS NULL
        THROW 78002,
            'No existe la tabla Existencias.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 45
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.TR_Variantes_InicializarExistencias',
            N'TR'
        ) IS NOT NULL
            THROW 78003,
                'El trigger existe sin migracion registrada.',
                1;

        -- Inicializar existencias para
        -- variantes creadas en el futuro.
        EXEC sys.sp_executesql N'
CREATE TRIGGER dbo.TR_Variantes_InicializarExistencias
ON dbo.Variantes
WITH EXECUTE AS OWNER
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Existencias (
        IDVariante,
        CantidadFisica
    )
    SELECT
        i.IDVariante,
        0
    FROM inserted i
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.Existencias e
            WITH (UPDLOCK, HOLDLOCK)
        WHERE e.IDVariante = i.IDVariante
    );
END;
';

        -- Reparar variantes existentes que
        -- quedaron sin registro de stock.
        -- No modificar inventarios existentes.
        INSERT INTO dbo.Existencias (
            IDVariante,
            CantidadFisica
        )
        SELECT
            v.IDVariante,
            0
        FROM dbo.Variantes v
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.Existencias e
                WITH (UPDLOCK, HOLDLOCK)
            WHERE e.IDVariante = v.IDVariante
        );

        DECLARE @Reparadas INT = @@ROWCOUNT;

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            45,
            N'045_FixVariantInventoryInitialization'
        );

        SELECT
            @Reparadas AS VariantesReparadas,
            'Migracion 045 aplicada correctamente'
                AS Resultado;
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.TR_Variantes_InicializarExistencias',
            N'TR'
        ) IS NULL
            THROW 78004,
                'Migracion registrada sin trigger.', 1;

        PRINT 'Migracion 045 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
