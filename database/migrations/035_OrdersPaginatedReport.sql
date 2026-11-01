USE ShopCartDB;
GO

SET NOCOUNT ON;
GO

-- ==========================================
-- MIGRACION 035
-- LISTADO PAGINADO DE PEDIDOS
-- RF-08
-- ==========================================

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 34
)
    THROW 72100,
        'Primero ejecute la migracion 034.',
        1;
GO

CREATE OR ALTER PROCEDURE dbo.SP_Reportes_ListarPedidos
    @IDUsuario INT,
    @Estado VARCHAR(20) = NULL,
    @IDCliente INT = NULL,
    @FechaInicio DATE = NULL,
    @FechaFin DATE = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    -- ======================================
    -- 1. SEGURIDAD
    -- ======================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r
            ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1
          AND r.Nombre IN (
              'Administrador',
              'Operador'
          )
    )
        THROW 72110,
            'Usuario no autorizado para consultar pedidos.',
            1;

    -- ======================================
    -- 2. VALIDACIONES
    -- ======================================

    IF @Pagina IS NULL OR @Pagina < 1
        THROW 72111,
            'Numero de pagina invalido.', 1;

    IF @TamanoPagina IS NULL
       OR @TamanoPagina NOT BETWEEN 1 AND 100
        THROW 72112,
            'Tamano de pagina invalido.', 1;

    IF @IDCliente IS NOT NULL
       AND @IDCliente <= 0
        THROW 72113,
            'Cliente invalido.', 1;

    IF @Estado IS NOT NULL
       AND @Estado NOT IN (
           'PAGADO',
           'PREPARANDO',
           'DESPACHADO',
           'ENTREGADO',
           'CANCELADO',
           'DEVUELTO_PARCIAL',
           'DEVUELTO_TOTAL'
       )
        THROW 72114,
            'Estado de pedido invalido.', 1;

    IF @FechaInicio IS NOT NULL
       AND @FechaFin IS NOT NULL
       AND @FechaInicio > @FechaFin
        THROW 72115,
            'Rango de fechas invalido.', 1;

    IF @FechaFin = '99991231'
        THROW 72116,
            'Fecha final fuera de rango.', 1;

    -- Fecha final inclusiva:
    -- se convierte en limite exclusivo.
    DECLARE @Hasta DATETIME2(3) = NULL;

    IF @FechaFin IS NOT NULL
        SET @Hasta = DATEADD(
            DAY,
            1,
            CONVERT(DATETIME2(3), @FechaFin)
        );

    DECLARE @Desplazamiento BIGINT =
        (CONVERT(BIGINT, @Pagina) - 1)
        * @TamanoPagina;

    DECLARE @TotalRegistros BIGINT;

    -- ======================================
    -- 3. FILTRAR PEDIDOS
    -- ======================================

    CREATE TABLE #PedidosFiltrados (
        IDPedido BIGINT NOT NULL PRIMARY KEY,
        FechaCreacion DATETIME2(3) NOT NULL
    );

    INSERT INTO #PedidosFiltrados (
        IDPedido,
        FechaCreacion
    )
    SELECT
        p.IDPedido,
        p.FechaCreacion
    FROM dbo.Pedidos p
    WHERE
        (
            @Estado IS NULL
            OR p.Estado = @Estado
        )
        AND (
            @IDCliente IS NULL
            OR p.IDUsuario = @IDCliente
        )
        AND (
            @FechaInicio IS NULL
            OR p.FechaCreacion >= @FechaInicio
        )
        AND (
            @Hasta IS NULL
            OR p.FechaCreacion < @Hasta
        );

    SELECT
        @TotalRegistros = COUNT_BIG(*)
    FROM #PedidosFiltrados;

    -- ======================================
    -- 4. DEVOLVER PAGINA SOLICITADA
    -- ======================================

    SELECT
        p.IDPedido,
        p.IDUsuario,
        p.Estado,
        p.Subtotal,
        p.Descuento,
        p.Total,
        p.CodigoCupon,

        CONVERT(
            DECIMAL(19,2),
            ISNULL(d.MontoDevuelto, 0)
        ) AS MontoDevuelto,

        -- Solo reconocemos ventas completadas.
        CONVERT(
            DECIMAL(19,2),
            CASE
                WHEN p.Estado IN (
                    'ENTREGADO',
                    'DEVUELTO_PARCIAL',
                    'DEVUELTO_TOTAL'
                )
                THEN
                    CASE
                        WHEN p.Total
                             - ISNULL(d.MontoDevuelto, 0) < 0
                        THEN 0
                        ELSE p.Total
                             - ISNULL(d.MontoDevuelto, 0)
                    END
                ELSE 0
            END
        ) AS VentaNeta,

        p.FechaCreacion,
        p.FechaActualizacion

    FROM #PedidosFiltrados f
    INNER JOIN dbo.Pedidos p
        ON p.IDPedido = f.IDPedido

    OUTER APPLY (
        SELECT
            SUM(dev.MontoReembolso)
                AS MontoDevuelto
        FROM dbo.Devoluciones dev
        WHERE dev.IDPedido = p.IDPedido
    ) d

    ORDER BY
        f.FechaCreacion DESC,
        f.IDPedido DESC

    OFFSET @Desplazamiento ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;

    -- ======================================
    -- 5. METADATOS DE PAGINACION
    -- Segundo resultset.
    -- ======================================

    SELECT
        @Pagina AS Pagina,
        @TamanoPagina AS TamanoPagina,
        @TotalRegistros AS TotalRegistros,

        CASE
            WHEN @TotalRegistros = 0 THEN
                CONVERT(BIGINT, 0)
            ELSE
                (
                    @TotalRegistros
                    + @TamanoPagina - 1
                ) / @TamanoPagina
        END AS TotalPaginas;
END;
GO

-- ==========================================
-- 6. PERMISOS Y REGISTRO
-- ==========================================

SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Reportes_ListarPedidos
    TO [shopcart_api];

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 35
    )
    BEGIN
        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            35,
            N'035_OrdersPaginatedReport'
        );
    END;

    COMMIT TRANSACTION;

    PRINT 'Migracion 035 aplicada correctamente.';

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
