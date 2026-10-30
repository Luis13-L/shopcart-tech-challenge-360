
USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- Verificar migracion anterior
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 16
    )
        THROW 65300,
            'Primero ejecute la migracion 016.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 17
    )
    BEGIN

        IF OBJECT_ID(
            N'dbo.SP_Catalogo_DesactivarProducto',
            N'P'
        ) IS NOT NULL
            THROW 65301,
                'El procedimiento ya existe.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_DesactivarProducto
    @IDUsuarioActor INT,
    @IDProducto INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IDProducto IS NULL OR @IDProducto <= 0
        THROW 65302, ''ID de producto invalido.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Verificar rol vigente del administrador
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios AS u
            INNER JOIN dbo.Roles AS r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = ''Administrador''
        )
            THROW 65303,
                ''Permisos administrativos insuficientes.'', 1;

        -- Bloquear y comprobar existencia del producto
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Productos WITH (UPDLOCK, HOLDLOCK)
            WHERE IDProducto = @IDProducto
        )
            THROW 65304,
                ''Producto no encontrado.'', 1;

        -- Desactivacion logica del producto
        UPDATE dbo.Productos
        SET Activo = 0
        WHERE IDProducto = @IDProducto
          AND Activo = 1;

        -- Desactivar variantes relacionadas
        UPDATE dbo.Variantes
        SET Activa = 0
        WHERE IDProducto = @IDProducto
          AND Activa = 1;

        DECLARE @VariantesDesactivadas INT = @@ROWCOUNT;

        -- Conservar inventario y kardex
        -- No se eliminan registros fisicamente

        COMMIT TRANSACTION;

        SELECT
            IDProducto,
            Nombre,
            Activo,
            @VariantesDesactivadas
                AS VariantesDesactivadas
        FROM dbo.Productos
        WHERE IDProducto = @IDProducto;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
';

        -- Permitir ejecucion a nuestra API
        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_DesactivarProducto
        TO [shopcart_api];

        -- Registrar migracion
        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            17,
            N'017_CatalogDeactivateProductProcedure'
        );

        PRINT 'Migracion 017 aplicada correctamente.';
    END
    ELSE
    BEGIN
        PRINT 'Migracion 017 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
