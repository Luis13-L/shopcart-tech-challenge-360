USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ==========================================
-- MIGRACION 057
-- LISTADO ADMINISTRATIVO DE PRODUCTOS
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    -- ======================================
    -- 1. VALIDAR DEPENDENCIA
    -- ======================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 56
    )
        THROW 80100,
            'Primero ejecute la migracion 056.',
            1;

    -- ======================================
    -- 2. EVITAR DUPLICAR MIGRACION
    -- ======================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 57
    )
    BEGIN

        IF OBJECT_ID(
            N'dbo.SP_Catalogo_ListarProductosAdmin',
            N'P'
        ) IS NOT NULL
            THROW 80101,
                'El procedimiento ya existe sin migracion.',
                1;

        -- ==================================
        -- 3. CREAR STORED PROCEDURE
        -- ==================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_ListarProductosAdmin
    @IDUsuarioActor INT,
    @Pagina INT = 1,
    @TamanoPagina INT = 10,
    @Busqueda NVARCHAR(120) = NULL,
    @Activo BIT = NULL,
    @IDCategoria INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- ======================================
    -- VALIDAR ADMINISTRADOR ACTIVO
    -- ======================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios AS u
        INNER JOIN dbo.Roles AS r
            ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuarioActor
          AND u.Activo = 1
          AND r.Nombre = ''Administrador''
    )
        THROW 80110,
            ''Administrador no autorizado.'',
            1;

    -- ======================================
    -- VALIDAR PAGINACION
    -- ======================================

    IF @Pagina IS NULL
       OR @Pagina NOT BETWEEN 1 AND 10000
       OR @TamanoPagina IS NULL
       OR @TamanoPagina NOT BETWEEN 1 AND 50
        THROW 80111,
            ''Paginacion invalida.'',
            1;

    IF @IDCategoria IS NOT NULL
       AND @IDCategoria <= 0
        THROW 80112,
            ''Categoria invalida.'',
            1;

    -- ======================================
    -- NORMALIZAR BUSQUEDA
    -- ======================================

    SET @Busqueda = NULLIF(
        LTRIM(RTRIM(@Busqueda)),
        N''''
    );

    DECLARE @Offset BIGINT =
        (CONVERT(BIGINT, @Pagina) - 1)
        * @TamanoPagina;

    -- ======================================
    -- MATERIALIZAR PRODUCTOS FILTRADOS
    -- UNA FILA POR PRODUCTO
    -- ======================================

    SELECT
        p.IDProducto,
        p.Nombre AS NombreProducto,
        p.Descripcion,
        p.Activo,
        p.FechaCreacion,

        c.IDCategoria,
        c.Nombre AS NombreCategoria,
        c.Activa AS CategoriaActiva,

        principal.IDVariante
            AS IDVarianteReferencia,

        principal.SKU
            AS SKUReferencia,

        CONVERT(
            VARCHAR(32),
            principal.PrecioActual
        ) AS PrecioReferencia,

        principal.Activa
            AS VarianteReferenciaActiva,

        ISNULL(
            e.CantidadFisica, 0
        ) AS CantidadFisicaReferencia,

        totales.TotalVariantes,

        ISNULL(
            totales.VariantesActivas,
            0
        ) AS VariantesActivas,

        imagen.URLImagen,
        imagen.TextoAlternativo

    INTO #ProductosFiltrados

    FROM dbo.Productos AS p

    INNER JOIN dbo.Categorias AS c
        ON c.IDCategoria = p.IDCategoria

    -- Elegir variante de referencia:
    -- activa primero, luego menor ID.

    OUTER APPLY (
        SELECT TOP (1)
            v.IDVariante,
            v.SKU,
            v.PrecioActual,
            v.Activa
        FROM dbo.Variantes AS v
        WHERE v.IDProducto = p.IDProducto
        ORDER BY
            v.Activa DESC,
            v.IDVariante ASC
    ) AS principal

    -- Contar todas las variantes.

    OUTER APPLY (
        SELECT
            COUNT(*) AS TotalVariantes,

            SUM(
                CASE
                    WHEN v.Activa = 1 THEN 1
                    ELSE 0
                END
            ) AS VariantesActivas

        FROM dbo.Variantes AS v
        WHERE v.IDProducto = p.IDProducto
    ) AS totales

    LEFT JOIN dbo.Existencias AS e
        ON e.IDVariante = principal.IDVariante

    -- Consultar miniatura existente.
    -- No modifica ni reemplaza imagenes.

    OUTER APPLY (
        SELECT TOP (1)
            i.URLImagen,
            i.TextoAlternativo
        FROM dbo.ImagenesProducto AS i
        WHERE i.IDProducto = p.IDProducto
        ORDER BY
            i.OrdenVisualizacion,
            i.IDImagenProducto
    ) AS imagen

    WHERE
        (
            @Activo IS NULL
            OR p.Activo = @Activo
        )

        AND (
            @IDCategoria IS NULL
            OR p.IDCategoria = @IDCategoria
        )

        AND (
            @Busqueda IS NULL

            OR CHARINDEX(
                @Busqueda,
                p.Nombre
            ) > 0

            OR EXISTS (
                SELECT 1
                FROM dbo.Variantes AS v
                WHERE v.IDProducto = p.IDProducto
                  AND CHARINDEX(
                      @Busqueda,
                      v.SKU
                  ) > 0
            )
        );

    -- ======================================
    -- RESULTADO 1: TOTAL DE PRODUCTOS
    -- ======================================

    SELECT
        COUNT_BIG(*) AS Total
    FROM #ProductosFiltrados;

    -- ======================================
    -- RESULTADO 2: PAGINA SOLICITADA
    -- ======================================

    SELECT
        IDProducto,
        NombreProducto,
        Descripcion,
        Activo,
        FechaCreacion,

        IDCategoria,
        NombreCategoria,
        CategoriaActiva,

        IDVarianteReferencia,
        SKUReferencia,
        PrecioReferencia,
        VarianteReferenciaActiva,

        CantidadFisicaReferencia,
        TotalVariantes,
        VariantesActivas,

        URLImagen,
        TextoAlternativo

    FROM #ProductosFiltrados

    ORDER BY
        NombreProducto ASC,
        IDProducto ASC

    OFFSET @Offset ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;

END;
';

        -- ==================================
        -- 4. VERIFICAR USUARIO DE LA API
        -- ==================================

        IF DATABASE_PRINCIPAL_ID(
            N'shopcart_api'
        ) IS NULL
            THROW 80102,
                'No existe el usuario shopcart_api.',
                1;

        -- ==================================
        -- 5. PERMISO MINIMO
        -- ==================================

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_ListarProductosAdmin
        TO [shopcart_api];

        -- ==================================
        -- 6. REGISTRAR MIGRACION
        -- ==================================

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            57,
            N'057_AdminProductsListProcedure'
        );

        PRINT
            'OK: Migracion 057 aplicada correctamente.';

    END
    ELSE
    BEGIN

        IF OBJECT_ID(
            N'dbo.SP_Catalogo_ListarProductosAdmin',
            N'P'
        ) IS NULL
            THROW 80103,
                'Migracion registrada sin procedimiento.',
                1;

        PRINT
            'OK: Migracion 057 ya aplicada.';

    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO
