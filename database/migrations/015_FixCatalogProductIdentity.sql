
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
        WHERE Numero = 14
    )
        THROW 65130,
            'Primero ejecute la migracion 014.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 15
    )
    BEGIN
        -- Confirmar que ambas columnas son IDENTITY
        IF COLUMNPROPERTY(
            OBJECT_ID(N'dbo.Productos'),
            'IDProducto',
            'IsIdentity'
        ) <> 1
        OR COLUMNPROPERTY(
            OBJECT_ID(N'dbo.Variantes'),
            'IDVariante',
            'IsIdentity'
        ) <> 1
            THROW 65131,
                'Las columnas deben ser IDENTITY.', 1;

        EXEC sys.sp_executesql N'
ALTER PROCEDURE dbo.SP_Catalogo_CrearProducto
    @IDUsuarioActor INT,
    @IDCategoria INT,
    @Nombre NVARCHAR(200),
    @Descripcion NVARCHAR(2000) = NULL,
    @SKU NVARCHAR(64),
    @PrecioActual DECIMAL(19,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Nombre = LTRIM(RTRIM(@Nombre));
    SET @SKU = UPPER(LTRIM(RTRIM(@SKU)));

    IF @Nombre IS NULL OR LEN(@Nombre) < 3
        THROW 65104, ''Nombre de producto invalido.'', 1;

    IF @SKU IS NULL OR LEN(@SKU) < 3
        THROW 65105, ''SKU invalido.'', 1;

    IF @PrecioActual IS NULL OR @PrecioActual <= 0
        THROW 65106, ''Precio invalido.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Verificar permisos vigentes
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios AS u
            INNER JOIN dbo.Roles AS r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = ''Administrador''
        )
            THROW 65107,
                ''Usuario sin permisos administrativos.'', 1;

        -- Verificar categoria activa
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Categorias
            WHERE IDCategoria = @IDCategoria
              AND Activa = 1
        )
            THROW 65108,
                ''Categoria inexistente o inactiva.'', 1;

        -- Prevenir SKU duplicado
        IF EXISTS (
            SELECT 1
            FROM dbo.Variantes WITH (UPDLOCK, HOLDLOCK)
            WHERE SKU = @SKU
        )
            THROW 65109, ''El SKU ya existe.'', 1;

        DECLARE @IDProducto INT;
        DECLARE @IDVariante INT;

        -- Crear producto: SQL Server genera el ID
        INSERT INTO dbo.Productos (
            IDCategoria,
            Nombre,
            Descripcion,
            Activo,
            FechaCreacion
        )
        VALUES (
            @IDCategoria,
            @Nombre,
            @Descripcion,
            1,
            SYSUTCDATETIME()
        );

        SET @IDProducto =
            CONVERT(INT, SCOPE_IDENTITY());

        -- Crear variante: SQL Server genera el ID
        INSERT INTO dbo.Variantes (
            IDProducto,
            SKU,
            PrecioActual,
            Activa,
            FechaCreacion
        )
        VALUES (
            @IDProducto,
            @SKU,
            @PrecioActual,
            1,
            SYSUTCDATETIME()
        );

        SET @IDVariante =
            CONVERT(INT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;

        SELECT
            @IDProducto AS IDProducto,
            @IDVariante AS IDVariante,
            @Nombre AS Nombre,
            @SKU AS SKU,
            @PrecioActual AS PrecioActual;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
';

        -- Eliminar secuencias innecesarias de la 014
        IF EXISTS (
            SELECT 1 FROM sys.sequences
            WHERE name = N'Seq_Productos'
              AND schema_id = SCHEMA_ID(N'dbo')
        )
            DROP SEQUENCE dbo.Seq_Productos;

        IF EXISTS (
            SELECT 1 FROM sys.sequences
            WHERE name = N'Seq_Variantes'
              AND schema_id = SCHEMA_ID(N'dbo')
        )
            DROP SEQUENCE dbo.Seq_Variantes;

        -- Mantener permiso de ejecucion
        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_CrearProducto
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            15,
            N'015_FixCatalogProductIdentity'
        );

        PRINT 'Migracion 015 aplicada correctamente.';
    END
    ELSE
        PRINT 'Migracion 015 ya aplicada.';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
