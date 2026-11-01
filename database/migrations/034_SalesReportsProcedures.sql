USE ShopCartDB;
GO

SET NOCOUNT ON;
GO

-- ==========================================
-- PASO 32 - REPORTES DE VENTAS
-- MIGRACION 034
--
-- RF-08:
-- Ventas por periodo, categoria y top 10.
-- Solo pedidos entregados o devueltos.
-- Importes netos de descuentos y reembolsos.
-- ==========================================

-- ==========================================
-- 1. VISTA INTERNA DE VENTAS NETAS
-- ==========================================

CREATE OR ALTER VIEW dbo.VW_Reportes_VentasDetalle
AS
WITH Reembolsos AS (
    SELECT
        dd.IDDetallePedido,
        SUM(d.MontoReembolso) AS MontoDevuelto
    FROM dbo.DetallesDevolucion dd
    INNER JOIN dbo.Devoluciones d
        ON d.IDDevolucion = dd.IDDevolucion
    GROUP BY dd.IDDetallePedido
),
Lineas AS (
    SELECT
        p.IDPedido,
        p.FechaCreacion AS FechaVenta,
        p.Subtotal,
        p.Descuento,

        dp.IDDetallePedido,
        dp.IDVariante,
        dp.IDCategoria,
        dp.SKU,
        dp.NombreProducto,
        dp.Cantidad,
        dp.CantidadDevuelta,
        dp.ImporteLinea,

        ISNULL(
            r.MontoDevuelto,
            CONVERT(DECIMAL(19,2), 0)
        ) AS MontoDevuelto,

        -- Asignacion proporcional del descuento
        -- entre las lineas del pedido.
        CONVERT(
            DECIMAL(19,2),
            CASE
                WHEN p.Subtotal = 0 THEN 0
                ELSE ROUND(
                    p.Descuento
                    * dp.ImporteLinea
                    / p.Subtotal,
                    2
                )
            END
        ) AS DescuentoProporcional

    FROM dbo.Pedidos p
    INNER JOIN dbo.DetallesPedido dp
        ON dp.IDPedido = p.IDPedido
    LEFT JOIN Reembolsos r
        ON r.IDDetallePedido = dp.IDDetallePedido

    WHERE p.Estado IN (
        'ENTREGADO',
        'DEVUELTO_PARCIAL',
        'DEVUELTO_TOTAL'
    )
),
DescuentosAsignados AS (
    SELECT
        l.*,

        -- Ajustar el redondeo en la ultima linea,
        -- garantizando que la suma de descuentos
        -- coincida con el descuento del pedido.
        CONVERT(
            DECIMAL(19,2),
            CASE
                WHEN ROW_NUMBER() OVER (
                    PARTITION BY l.IDPedido
                    ORDER BY l.IDDetallePedido DESC
                ) = 1
                THEN
                    l.Descuento
                    - SUM(
                        l.DescuentoProporcional
                    ) OVER (
                        PARTITION BY l.IDPedido
                    )
                    + l.DescuentoProporcional
                ELSE
                    l.DescuentoProporcional
            END
        ) AS DescuentoAsignado

    FROM Lineas l
)
SELECT
    IDPedido,
    FechaVenta,
    IDDetallePedido,
    IDVariante,
    IDCategoria,
    SKU,
    NombreProducto,

    Cantidad,
    CantidadDevuelta,

    Cantidad - CantidadDevuelta
        AS CantidadNeta,

    ImporteLinea,
    DescuentoAsignado,
    MontoDevuelto,

    CONVERT(
        DECIMAL(19,2),
        ImporteLinea
        - DescuentoAsignado
        - MontoDevuelto
    ) AS ImporteNeto

FROM DescuentosAsignados;
GO

-- ==========================================
-- 2. VENTAS POR DIA, SEMANA O MES
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Reportes_VentasPeriodo
    @IDUsuario INT,
    @FechaInicio DATE,
    @FechaFin DATE,
    @Agrupacion VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    -- Solo Administradores.
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r
            ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1
          AND r.Nombre = 'Administrador'
    )
        THROW 72010,
            'Usuario no autorizado para reportes.',
            1;

    IF @FechaInicio IS NULL
       OR @FechaFin IS NULL
       OR @FechaInicio > @FechaFin
       OR @FechaFin >= '9999-12-31'
        THROW 72011,
            'Rango de fechas invalido.',
            1;

    IF @Agrupacion IS NULL
       OR @Agrupacion NOT IN (
           'DIA',
           'SEMANA',
           'MES'
       )
        THROW 72012,
            'Agrupacion invalida.',
            1;

    DECLARE @Hasta DATETIME2(3) =
        DATEADD(
            DAY,
            1,
            CONVERT(DATETIME2(3), @FechaFin)
        );

    ;WITH Periodos AS (
        SELECT
            v.IDPedido,
            v.ImporteNeto,

            CASE @Agrupacion

                WHEN 'DIA' THEN
                    CONVERT(DATE, v.FechaVenta)

                WHEN 'SEMANA' THEN
                    DATEADD(
                        DAY,
                        -(
                            DATEDIFF(
                                DAY,
                                CONVERT(DATE, '19000101'),
                                CONVERT(DATE, v.FechaVenta)
                            ) % 7
                        ),
                        CONVERT(DATE, v.FechaVenta)
                    )

                WHEN 'MES' THEN
                    DATEFROMPARTS(
                        YEAR(v.FechaVenta),
                        MONTH(v.FechaVenta),
                        1
                    )
            END AS Periodo

        FROM dbo.VW_Reportes_VentasDetalle v

        WHERE v.FechaVenta >= @FechaInicio
          AND v.FechaVenta < @Hasta
    )
    SELECT
        Periodo,

        COUNT(DISTINCT IDPedido)
            AS CantidadPedidos,

        CONVERT(
            DECIMAL(19,2),
            SUM(ImporteNeto)
        ) AS VentasNetas

    FROM Periodos
    GROUP BY Periodo
    ORDER BY Periodo;
END;
GO

-- ==========================================
-- 3. VENTAS POR CATEGORIA
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Reportes_VentasCategoria
    @IDUsuario INT,
    @FechaInicio DATE,
    @FechaFin DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r
            ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1
          AND r.Nombre = 'Administrador'
    )
        THROW 72010,
            'Usuario no autorizado para reportes.',
            1;

    IF @FechaInicio IS NULL
       OR @FechaFin IS NULL
       OR @FechaInicio > @FechaFin
       OR @FechaFin >= '9999-12-31'
        THROW 72011,
            'Rango de fechas invalido.',
            1;

    DECLARE @Hasta DATETIME2(3) =
        DATEADD(
            DAY,
            1,
            CONVERT(DATETIME2(3), @FechaFin)
        );

    SELECT
        v.IDCategoria,

        COUNT(DISTINCT v.IDPedido)
            AS CantidadPedidos,

        SUM(v.CantidadNeta)
            AS UnidadesNetas,

        CONVERT(
            DECIMAL(19,2),
            SUM(v.ImporteNeto)
        ) AS VentasNetas

    FROM dbo.VW_Reportes_VentasDetalle v

    WHERE v.FechaVenta >= @FechaInicio
      AND v.FechaVenta < @Hasta

    GROUP BY v.IDCategoria

    ORDER BY VentasNetas DESC,
             v.IDCategoria;
END;
GO

-- ==========================================
-- 4. TOP 10 PRODUCTOS MAS VENDIDOS
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Reportes_TopProductos
    @IDUsuario INT,
    @FechaInicio DATE,
    @FechaFin DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r
            ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1
          AND r.Nombre = 'Administrador'
    )
        THROW 72010,
            'Usuario no autorizado para reportes.',
            1;

    IF @FechaInicio IS NULL
       OR @FechaFin IS NULL
       OR @FechaInicio > @FechaFin
       OR @FechaFin >= '9999-12-31'
        THROW 72011,
            'Rango de fechas invalido.',
            1;

    DECLARE @Hasta DATETIME2(3) =
        DATEADD(
            DAY,
            1,
            CONVERT(DATETIME2(3), @FechaFin)
        );

    SELECT TOP (10)
        v.IDVariante,
        v.SKU,
        MAX(v.NombreProducto)
            AS NombreProducto,

        SUM(v.CantidadNeta)
            AS UnidadesVendidas,

        CONVERT(
            DECIMAL(19,2),
            SUM(v.ImporteNeto)
        ) AS VentasNetas

    FROM dbo.VW_Reportes_VentasDetalle v

    WHERE v.FechaVenta >= @FechaInicio
      AND v.FechaVenta < @Hasta

    GROUP BY
        v.IDVariante,
        v.SKU

    HAVING SUM(v.CantidadNeta) > 0

    ORDER BY
        UnidadesVendidas DESC,
        VentasNetas DESC,
        v.IDVariante;
END;
GO

-- ==========================================
-- 5. PERMISOS Y REGISTRO DE MIGRACION
-- ==========================================

SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 33
    )
        THROW 72001,
            'Primero ejecute la migracion 033.',
            1;

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Reportes_VentasPeriodo
    TO [shopcart_api];

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Reportes_VentasCategoria
    TO [shopcart_api];

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Reportes_TopProductos
    TO [shopcart_api];

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (
            UPDLOCK,
            HOLDLOCK
        )
        WHERE Numero = 34
    )
    BEGIN
        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            34,
            N'034_SalesReportsProcedures'
        );
    END;

    COMMIT TRANSACTION;

    PRINT 'Migracion 034 aplicada correctamente.';

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
