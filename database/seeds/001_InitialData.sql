
-- ================================================
-- PROYECTO: ShopCart
-- SEED: 001_InitialData.sql
-- OBJETIVO: Datos iniciales de desarrollo
-- ================================================

USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- ==========================================
    -- 1. ROLES
    -- ==========================================

    INSERT INTO dbo.Roles (Nombre)
    SELECT r.Nombre
    FROM (
        VALUES
            ('Cliente'),
            ('Operador'),
            ('Administrador')
    ) AS r(Nombre)
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.Roles AS x WITH (UPDLOCK, HOLDLOCK)
        WHERE x.Nombre = r.Nombre
    );

    -- ==========================================
    -- 2. CATEGORIA
    -- ==========================================

    DECLARE @IDCategoria INT;
    DECLARE @IDProducto INT;
    DECLARE @IDVariante INT;

    SELECT @IDCategoria = IDCategoria
    FROM dbo.Categorias WITH (UPDLOCK, HOLDLOCK)
    WHERE Nombre = N'Accesorios';

    IF @IDCategoria IS NULL
    BEGIN
        INSERT INTO dbo.Categorias (
            Nombre,
            Descripcion
        )
        VALUES (
            N'Accesorios',
            N'Accesorios para uso diario'
        );

        SET @IDCategoria = SCOPE_IDENTITY();
    END;

    -- ==========================================
    -- 3. PRODUCTO Y VARIANTE
    -- ==========================================

    SELECT
        @IDVariante = IDVariante,
        @IDProducto = IDProducto
    FROM dbo.Variantes WITH (UPDLOCK, HOLDLOCK)
    WHERE SKU = N'BOT-500-NEG';

    IF @IDVariante IS NULL
    BEGIN
        INSERT INTO dbo.Productos (
            IDCategoria,
            Nombre,
            Descripcion
        )
        VALUES (
            @IDCategoria,
            N'Botella termica',
            N'Botella reutilizable de 500 ml'
        );

        SET @IDProducto = SCOPE_IDENTITY();

        INSERT INTO dbo.Variantes (
            IDProducto,
            SKU,
            PrecioActual
        )
        VALUES (
            @IDProducto,
            N'BOT-500-NEG',
            150.00
        );

        SET @IDVariante = SCOPE_IDENTITY();
    END;

    -- ==========================================
    -- 4. EXISTENCIA INICIAL
    -- ==========================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Existencias WITH (UPDLOCK, HOLDLOCK)
        WHERE IDVariante = @IDVariante
    )
    BEGIN
        INSERT INTO dbo.Existencias (
            IDVariante,
            CantidadFisica
        )
        VALUES (
            @IDVariante,
            0
        );
    END;

    COMMIT TRANSACTION;

    PRINT 'Datos iniciales creados correctamente.';

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO

-- ================================================
-- VERIFICAR DATOS CREADOS
-- ================================================

SELECT IDRol, Nombre
FROM dbo.Roles
ORDER BY IDRol;

SELECT
    p.IDProducto,
    p.Nombre AS Producto,
    v.IDVariante,
    v.SKU,
    v.PrecioActual,
    e.CantidadFisica
FROM dbo.Productos AS p
INNER JOIN dbo.Variantes AS v
    ON v.IDProducto = p.IDProducto
INNER JOIN dbo.Existencias AS e
    ON e.IDVariante = v.IDVariante
WHERE v.SKU = N'BOT-500-NEG';
GO
