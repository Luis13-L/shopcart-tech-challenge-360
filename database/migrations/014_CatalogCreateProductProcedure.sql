
USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- Validar migracion anterior
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 13
    )
        THROW 65100,
            'Primero ejecute la migracion 013.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 14
    )
    BEGIN

        -- ==========================================
        -- 1. CREAR SECUENCIAS PARA LOS IDENTIFICADORES
        -- ==========================================

        IF EXISTS (
            SELECT 1 FROM sys.sequences
            WHERE name IN (
                'Seq_Productos',
                'Seq_Variantes'
            )
            AND schema_id = SCHEMA_ID('dbo')
        )
            THROW 65101,
                'Ya existe una secuencia del catalogo.', 1;

        DECLARE @SiguienteProducto BIGINT;
        DECLARE @SiguienteVariante BIGINT;
        DECLARE @SQL NVARCHAR(MAX);

        SELECT @SiguienteProducto =
            ISNULL(MAX(CONVERT(BIGINT, IDProducto)), 0) + 1
        FROM dbo.Productos;

        SELECT @SiguienteVariante =
            ISNULL(MAX(CONVERT(BIGINT, IDVariante)), 0) + 1
        FROM dbo.Variantes;

        IF @SiguienteProducto > 2147483647
           OR @SiguienteVariante > 2147483647
            THROW 65102,
                'Se agoto el rango de identificadores INT.', 1;

        SET @SQL = N'
            CREATE SEQUENCE dbo.Seq_Productos
            AS INT
            START WITH ' +
            CAST(@SiguienteProducto AS NVARCHAR(20)) + N'
            INCREMENT BY 1
            MINVALUE 1
            MAXVALUE 2147483647
            NO CYCLE
            NO CACHE;
        ';

        EXEC sys.sp_executesql @SQL;

        SET @SQL = N'
            CREATE SEQUENCE dbo.Seq_Variantes
            AS INT
            START WITH ' +
            CAST(@SiguienteVariante AS NVARCHAR(20)) + N'
            INCREMENT BY 1
            MINVALUE 1
            MAXVALUE 2147483647
            NO CYCLE
            NO CACHE;
        ';

        EXEC sys.sp_executesql @SQL;

        -- ==========================================
        -- 2. CREAR STORED PROCEDURE
        -- ==========================================

        IF OBJECT_ID(
            N'dbo.SP_Catalogo_CrearProducto', N'P'
        ) IS NOT NULL
            THROW 65103,
                'El procedimiento ya existe.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_CrearProducto
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

    -- Validaciones basicas
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

        -- Comprobar permisos ACTUALES del usuario
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

        -- Comprobar categoria activa
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Categorias
            WHERE IDCategoria = @IDCategoria
              AND Activa = 1
        )
            THROW 65108,
                ''Categoria inexistente o inactiva.'', 1;

        -- Comprobar SKU existente
        IF EXISTS (
            SELECT 1
            FROM dbo.Variantes WITH (UPDLOCK, HOLDLOCK)
            WHERE SKU = @SKU
        )
            THROW 65109,
                ''El SKU ya existe.'', 1;

        DECLARE @IDProducto INT;
        DECLARE @IDVariante INT;

        SELECT @IDProducto =
            NEXT VALUE FOR dbo.Seq_Productos;

        SELECT @IDVariante =
            NEXT VALUE FOR dbo.Seq_Variantes;

        -- Crear producto
        INSERT INTO dbo.Productos (
            IDProducto,
            IDCategoria,
            Nombre,
            Descripcion,
            Activo,
            FechaCreacion
        )
        VALUES (
            @IDProducto,
            @IDCategoria,
            @Nombre,
            @Descripcion,
            1,
            SYSUTCDATETIME()
        );

        -- Crear variante inicial
        INSERT INTO dbo.Variantes (
            IDVariante,
            IDProducto,
            SKU,
            PrecioActual,
            Activa,
            FechaCreacion
        )
        VALUES (
            @IDVariante,
            @IDProducto,
            @SKU,
            @PrecioActual,
            1,
            SYSUTCDATETIME()
        );

        COMMIT TRANSACTION;

        -- Respuesta para la API
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

        -- ==========================================
        -- 3. PERMISOS DEL USUARIO API
        -- ==========================================

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_CrearProducto
        TO [shopcart_api];

        -- ==========================================
        -- 4. REGISTRAR MIGRACION
        -- ==========================================

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            14,
            N'014_CatalogCreateProductProcedure'
        );

        PRINT 'Migracion 014 aplicada correctamente.';
    END
    ELSE
    BEGIN
        PRINT 'Migracion 014 ya fue aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
