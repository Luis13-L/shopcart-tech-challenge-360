
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
        WHERE Numero = 19
    )
        THROW 65500,
            'Primero ejecute la migracion 019.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 20
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Catalogo_CrearProducto', N'P'
        ) IS NULL
            THROW 65501,
                'No existe SP_Catalogo_CrearProducto.', 1;

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

        -- Validar permisos actuales
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
                ''Permisos insuficientes.'', 1;

        -- Validar categoria activa
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Categorias
            WHERE IDCategoria = @IDCategoria
              AND Activa = 1
        )
            THROW 65108,
                ''Categoria no disponible.'', 1;

        -- Verificar SKU duplicado
        IF EXISTS (
            SELECT 1
            FROM dbo.Variantes WITH (UPDLOCK, HOLDLOCK)
            WHERE SKU = @SKU
        )
            THROW 65109,
                ''El SKU ya existe.'', 1;

        DECLARE @IDProducto INT;
        DECLARE @IDVariante INT;

        -- 1. Crear producto
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

        -- 2. Crear variante
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

        -- 3. Inicializar inventario en cero
        INSERT INTO dbo.Existencias (
            IDVariante,
            CantidadFisica
        )
        VALUES (
            @IDVariante,
            0
        );

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

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_CrearProducto
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            20,
            N'020_InitializeProductInventory'
        );

        PRINT 'Migracion 020 aplicada correctamente.';
    END
    ELSE
        PRINT 'Migracion 020 ya aplicada.';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
