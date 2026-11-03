USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 46
)
    THROW 78500,
        'Primero ejecute la migracion 046.', 1;
GO

-- ============================================
-- RF-07: LISTAR MIS PEDIDOS
-- ============================================

CREATE OR ALTER PROCEDURE dbo.SP_Pedidos_ListarPropios
    @IDUsuario INT,
    @Estado VARCHAR(20) = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 10
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
          AND r.Nombre = 'Cliente'
    )
        THROW 78510, 'Cliente no autorizado.', 1;

    IF @Pagina IS NULL OR @Pagina < 1
       OR @TamanoPagina IS NULL
       OR @TamanoPagina NOT BETWEEN 1 AND 100
        THROW 78511, 'Paginacion invalida.', 1;

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
        THROW 78512, 'Estado invalido.', 1;

    DECLARE @TotalRegistros BIGINT;

    SELECT @TotalRegistros = COUNT_BIG(*)
    FROM dbo.Pedidos p
    WHERE p.IDUsuario = @IDUsuario
      AND (@Estado IS NULL OR p.Estado = @Estado);

    DECLARE @Offset BIGINT =
        (CONVERT(BIGINT, @Pagina) - 1)
        * @TamanoPagina;

    -- Primer resultset: pedidos
    SELECT
        p.IDPedido,
        p.Estado,
        p.Subtotal,
        p.Descuento,
        p.Total,
        p.CodigoCupon,
        p.FechaCreacion,
        p.FechaActualizacion
    FROM dbo.Pedidos p
    WHERE p.IDUsuario = @IDUsuario
      AND (@Estado IS NULL OR p.Estado = @Estado)
    ORDER BY
        p.FechaCreacion DESC,
        p.IDPedido DESC
    OFFSET @Offset ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;

    -- Segundo resultset: paginacion
    SELECT
        @Pagina AS Pagina,
        @TamanoPagina AS TamanoPagina,
        @TotalRegistros AS TotalRegistros,
        (
            @TotalRegistros + @TamanoPagina - 1
        ) / @TamanoPagina AS TotalPaginas;
END;
GO

-- ============================================
-- RF-07: DETALLE E HISTORIAL DE MI PEDIDO
-- ============================================

CREATE OR ALTER PROCEDURE dbo.SP_Pedidos_ObtenerPropio
    @IDUsuario INT,
    @IDPedido BIGINT
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
          AND r.Nombre = 'Cliente'
    )
        THROW 78510, 'Cliente no autorizado.', 1;

    IF @IDPedido IS NULL OR @IDPedido <= 0
        THROW 78513, 'Pedido invalido.', 1;

    -- Un pedido inexistente o ajeno devuelve
    -- exactamente el mismo error.
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pedidos
        WHERE IDPedido = @IDPedido
          AND IDUsuario = @IDUsuario
    )
        THROW 78521, 'Pedido no encontrado.', 1;

    -- Resultset 1: resumen y direccion historica
    SELECT
        p.IDPedido,
        p.Estado,
        p.Subtotal,
        p.Descuento,
        p.Total,
        p.CodigoCupon,
        p.EntregaDestinatario,
        p.EntregaTelefono,
        p.EntregaDepartamento,
        p.EntregaMunicipio,
        p.EntregaDireccionLinea1,
        p.EntregaReferencia,
        p.FechaCreacion,
        p.FechaActualizacion
    FROM dbo.Pedidos p
    WHERE p.IDPedido = @IDPedido
      AND p.IDUsuario = @IDUsuario;

    -- Resultset 2: productos con precios congelados
    SELECT
        d.IDDetallePedido,
        d.IDVariante,
        d.SKU,
        d.NombreProducto,
        d.PrecioUnitario,
        d.Cantidad,
        d.CantidadDevuelta,
        d.ImporteLinea
    FROM dbo.DetallesPedido d
    INNER JOIN dbo.Pedidos p
        ON p.IDPedido = d.IDPedido
    WHERE p.IDPedido = @IDPedido
      AND p.IDUsuario = @IDUsuario
    ORDER BY d.IDDetallePedido;

    -- Resultset 3: historial de estados
    SELECT
        h.IDHistorialPedido,
        h.EstadoAnterior,
        h.EstadoNuevo,
        h.Observacion,
        h.FechaCambio
    FROM dbo.HistorialEstadosPedido h
    INNER JOIN dbo.Pedidos p
        ON p.IDPedido = h.IDPedido
    WHERE p.IDPedido = @IDPedido
      AND p.IDUsuario = @IDUsuario
    ORDER BY
        h.FechaCambio ASC,
        h.IDHistorialPedido ASC;
END;
GO

-- ============================================
-- PERMISOS Y REGISTRO DE MIGRACION
-- ============================================

BEGIN TRY
    BEGIN TRANSACTION;

    IF DATABASE_PRINCIPAL_ID(N'shopcart_api') IS NULL
        THROW 78530,
            'No existe el usuario shopcart_api.', 1;

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Pedidos_ListarPropios
    TO [shopcart_api];

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Pedidos_ObtenerPropio
    TO [shopcart_api];

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 47
    )
    BEGIN
        INSERT INTO dbo.SchemaMigrations (
            Numero, Nombre
        )
        VALUES (
            47,
            N'047_CustomerOrderHistoryProcedures'
        );
    END;

    COMMIT TRANSACTION;

    PRINT 'Migracion 047 aplicada correctamente.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
