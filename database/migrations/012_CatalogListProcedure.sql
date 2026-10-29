
-- ==================================================
-- SHOPCART - MIGRACION 012
-- Catalogo: filtros, ordenamiento y paginacion
-- ==================================================

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
        WHERE Numero = 11
    )
        THROW 65001,
            'Primero ejecute la migracion 011.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 12
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Catalogo_ListarProductos', N'P'
        ) IS NOT NULL
            THROW 65002,
                'Procedimiento existente sin migracion.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_ListarProductos
    @Busqueda NVARCHAR(120) = NULL,
    @IDCategoria INT = NULL,
    @PrecioMin DECIMAL(19,2) = NULL,
    @PrecioMax DECIMAL(19,2) = NULL,
    @SoloDisponibles BIT = 0,
    @Orden VARCHAR(20) = ''name_asc'',
    @Pagina INT = 1,
    @TamPagina INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    -- Validacion de parametros
    IF @Pagina IS NULL
       OR @Pagina < 1
       OR @Pagina > 10000
        THROW 65003, ''Pagina invalida.'', 1;

    IF @TamPagina IS NULL
       OR @TamPagina < 1
       OR @TamPagina > 50
        THROW 65004, ''Tamano de pagina invalido.'', 1;

    IF @IDCategoria IS NOT NULL
       AND @IDCategoria <= 0
        THROW 65005, ''Categoria invalida.'', 1;

    IF @PrecioMin < 0 OR @PrecioMax < 0
        THROW 65006, ''Precio negativo.'', 1;

    IF @PrecioMin > @PrecioMax
        THROW 65007, ''Rango de precio invalido.'', 1;

    IF @Orden IS NULL OR @Orden NOT IN (
        ''name_asc'', ''name_desc'',
        ''price_asc'', ''price_desc''
    )
        THROW 65008, ''Orden invalido.'', 1;

    IF @SoloDisponibles IS NULL
        THROW 65009, ''Disponibilidad invalida.'', 1;

    DECLARE @Offset INT =
        (@Pagina - 1) * @TamPagina;

    -- Materializar un resultado consistente
    -- para el contador y los elementos.
    SELECT
        p.IDProducto,
        p.Nombre AS NombreProducto,
        c.IDCategoria,
        c.Nombre AS NombreCategoria,
        v.IDVariante,
        v.SKU,
        v.PrecioActual,
        ISNULL(e.CantidadFisica, 0)
            AS CantidadFisica
    INTO #ProductosFiltrados
    FROM dbo.Variantes AS v
    INNER JOIN dbo.Productos AS p
        ON p.IDProducto = v.IDProducto
    INNER JOIN dbo.Categorias AS c
        ON c.IDCategoria = p.IDCategoria
    LEFT JOIN dbo.Existencias AS e
        ON e.IDVariante = v.IDVariante
    WHERE p.Activo = 1
      AND v.Activa = 1
      AND c.Activa = 1
      AND (
          @Busqueda IS NULL
          OR p.Nombre LIKE N''%'' + @Busqueda + N''%''
          OR v.SKU LIKE N''%'' + @Busqueda + N''%''
      )
      AND (
          @IDCategoria IS NULL
          OR c.IDCategoria = @IDCategoria
      )
      AND (
          @PrecioMin IS NULL
          OR v.PrecioActual >= @PrecioMin
      )
      AND (
          @PrecioMax IS NULL
          OR v.PrecioActual <= @PrecioMax
      )
      AND (
          @SoloDisponibles = 0
          OR ISNULL(e.CantidadFisica, 0) > 0
      );

    -- Resultado 1: Total de registros
    SELECT COUNT(*) AS Total
    FROM #ProductosFiltrados;

    -- Resultado 2: Registros de la pagina
    SELECT
        IDProducto,
        NombreProducto,
        IDCategoria,
        NombreCategoria,
        IDVariante,
        SKU,
        CONVERT(VARCHAR(32), PrecioActual)
            AS PrecioActual,
        CantidadFisica
    FROM #ProductosFiltrados
    ORDER BY
        CASE WHEN @Orden = ''name_asc''
            THEN NombreProducto END ASC,

        CASE WHEN @Orden = ''name_desc''
            THEN NombreProducto END DESC,

        CASE WHEN @Orden = ''price_asc''
            THEN PrecioActual END ASC,

        CASE WHEN @Orden = ''price_desc''
            THEN PrecioActual END DESC,

        IDVariante ASC
    OFFSET @Offset ROWS
    FETCH NEXT @TamPagina ROWS ONLY;
END;
';

        -- Permiso para el backend
        IF DATABASE_PRINCIPAL_ID(
            N'shopcart_api'
        ) IS NULL
            THROW 65010,
                'Usuario shopcart_api no existe.', 1;

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_ListarProductos
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            12,
            N'012_CatalogListProcedure'
        );

        PRINT 'Migracion 012 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Catalogo_ListarProductos', N'P'
        ) IS NULL
            THROW 65011,
                'Migracion registrada sin procedimiento.', 1;

        PRINT 'Migracion 012 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
