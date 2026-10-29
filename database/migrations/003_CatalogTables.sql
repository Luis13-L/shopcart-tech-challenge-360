
-- ===================================================
-- PROYECTO: ShopCart
-- MIGRACION: 003_CatalogTables.sql
-- MODULO: Catalogo de productos
-- MOTOR: SQL Server 2019+
-- ===================================================

USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- Comprobar dependencia de la migracion 002
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 2
    )
    BEGIN
        THROW 50001,
            'Debe ejecutar primero la migracion 002.',
            1;
    END;

    -- Evitar aplicar nuevamente la migracion
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 3
    )
    BEGIN

        -- ======================================
        -- TABLA: Categorias
        -- ======================================
        CREATE TABLE dbo.Categorias (
            IDCategoria INT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_Categorias PRIMARY KEY,

            Nombre NVARCHAR(120)
                COLLATE Latin1_General_100_CI_AS
                NOT NULL,

            Descripcion NVARCHAR(500) NULL,

            Activa BIT NOT NULL
                CONSTRAINT DF_Categorias_Activa
                DEFAULT (1),

            FechaCreacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_Categorias_Fecha
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT UQ_Categorias_Nombre
                UNIQUE (Nombre),

            CONSTRAINT CK_Categorias_Nombre
                CHECK (
                    LEN(LTRIM(RTRIM(Nombre))) > 0
                )
        );

        -- ======================================
        -- TABLA: Productos
        -- ======================================
        CREATE TABLE dbo.Productos (
            IDProducto INT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_Productos PRIMARY KEY,

            IDCategoria INT NOT NULL,

            Nombre NVARCHAR(200) NOT NULL,

            Descripcion NVARCHAR(2000) NULL,

            Activo BIT NOT NULL
                CONSTRAINT DF_Productos_Activo
                DEFAULT (1),

            FechaCreacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_Productos_Fecha
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT FK_Productos_Categorias
                FOREIGN KEY (IDCategoria)
                REFERENCES dbo.Categorias(IDCategoria),

            CONSTRAINT CK_Productos_Nombre
                CHECK (
                    LEN(LTRIM(RTRIM(Nombre))) > 0
                )
        );

        -- ======================================
        -- TABLA: Variantes
        -- ======================================
        CREATE TABLE dbo.Variantes (
            IDVariante INT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_Variantes PRIMARY KEY,

            IDProducto INT NOT NULL,

            SKU NVARCHAR(64)
                COLLATE Latin1_General_100_CI_AS
                NOT NULL,

            PrecioActual DECIMAL(19,2) NOT NULL,

            Activa BIT NOT NULL
                CONSTRAINT DF_Variantes_Activa
                DEFAULT (1),

            FechaCreacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_Variantes_Fecha
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT FK_Variantes_Productos
                FOREIGN KEY (IDProducto)
                REFERENCES dbo.Productos(IDProducto),

            CONSTRAINT UQ_Variantes_SKU
                UNIQUE (SKU),

            CONSTRAINT CK_Variantes_Precio
                CHECK (PrecioActual >= 0),

            CONSTRAINT CK_Variantes_SKU
                CHECK (
                    LEN(LTRIM(RTRIM(SKU))) > 0
                )
        );

        -- ======================================
        -- TABLA: AtributosVariante
        -- ======================================
        CREATE TABLE dbo.AtributosVariante (
            IDAtributoVariante INT IDENTITY(1,1)
                NOT NULL
                CONSTRAINT PK_AtributosVariante
                PRIMARY KEY,

            IDVariante INT NOT NULL,

            Nombre NVARCHAR(60) NOT NULL,

            Valor NVARCHAR(100) NOT NULL,

            CONSTRAINT FK_AtributosVariante_Variantes
                FOREIGN KEY (IDVariante)
                REFERENCES dbo.Variantes(IDVariante),

            CONSTRAINT UQ_AtributosVariante_Nombre
                UNIQUE (IDVariante, Nombre),

            CONSTRAINT CK_AtributosVariante_Nombre
                CHECK (
                    LEN(LTRIM(RTRIM(Nombre))) > 0
                ),

            CONSTRAINT CK_AtributosVariante_Valor
                CHECK (
                    LEN(LTRIM(RTRIM(Valor))) > 0
                )
        );

        -- ======================================
        -- TABLA: ImagenesProducto
        -- ======================================
        CREATE TABLE dbo.ImagenesProducto (
            IDImagenProducto INT IDENTITY(1,1)
                NOT NULL
                CONSTRAINT PK_ImagenesProducto
                PRIMARY KEY,

            IDProducto INT NOT NULL,

            URLImagen NVARCHAR(1000) NOT NULL,

            TextoAlternativo NVARCHAR(250) NULL,

            OrdenVisualizacion INT NOT NULL
                CONSTRAINT DF_ImagenesProducto_Orden
                DEFAULT (0),

            CONSTRAINT FK_ImagenesProducto_Productos
                FOREIGN KEY (IDProducto)
                REFERENCES dbo.Productos(IDProducto),

            CONSTRAINT CK_ImagenesProducto_URL
                CHECK (
                    LEN(LTRIM(RTRIM(URLImagen))) > 0
                ),

            CONSTRAINT CK_ImagenesProducto_Orden
                CHECK (OrdenVisualizacion >= 0)
        );

        -- ======================================
        -- INDICES
        -- ======================================
        CREATE INDEX IX_Productos_CategoriaActivo
            ON dbo.Productos(IDCategoria, Activo);

        CREATE INDEX IX_Variantes_ProductoActivo
            ON dbo.Variantes(IDProducto, Activa);

        CREATE INDEX IX_ImagenesProducto_ProductoOrden
            ON dbo.ImagenesProducto(
                IDProducto,
                OrdenVisualizacion
            );

        -- ======================================
        -- REGISTRAR MIGRACION
        -- ======================================
        INSERT INTO dbo.SchemaMigrations
            (Numero, Nombre)
        VALUES
            (3, N'003_CatalogTables');

        PRINT 'Migracion 003 aplicada correctamente.';

    END
    ELSE
    BEGIN
        PRINT 'La migracion 003 ya fue aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
