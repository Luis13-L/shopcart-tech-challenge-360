USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 47
)
    THROW 78700,
        'Primero ejecute la migracion 047.', 1;
GO

-- ==========================================
-- CONSULTAR EXISTENCIAS DE UNA VARIANTE
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Inventario_ConsultarExistencia
    @IDUsuario INT,
    @IDVariante INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1
          AND r.Nombre IN ('Operador', 'Administrador')
    )
        THROW 78701, 'Usuario sin permisos.', 1;

    IF @IDVariante IS NULL OR @IDVariante <= 0
        THROW 78702, 'Variante invalida.', 1;

    SELECT
        e.IDVariante,
        v.SKU,
        e.CantidadFisica,
        ISNULL(res.CantidadReservada, 0)
            AS CantidadReservada,
        CONVERT(BIGINT, e.CantidadFisica)
            - ISNULL(res.CantidadReservada, 0)
            AS CantidadDisponible,
        e.FechaActualizacion
    FROM dbo.Existencias e
    INNER JOIN dbo.Variantes v
        ON v.IDVariante = e.IDVariante
    OUTER APPLY (
        SELECT SUM(CONVERT(BIGINT, dr.Cantidad))
            AS CantidadReservada
        FROM dbo.DetallesReserva dr
        INNER JOIN dbo.ReservasInventario r
            ON r.IDReserva = dr.IDReserva
        WHERE dr.IDVariante = e.IDVariante
          AND r.Estado = 'ACTIVA'
          AND r.ExpiraEn > SYSUTCDATETIME()
    ) res
    WHERE e.IDVariante = @IDVariante;
END;
GO

-- ==========================================
-- CONSULTAR KARDEX PAGINADO
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Inventario_ListarKardex
    @IDUsuario INT,
    @IDVariante INT,
    @Pagina INT = 1,
    @TamanoPagina INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1
          AND r.Nombre IN ('Operador', 'Administrador')
    )
        THROW 78701, 'Usuario sin permisos.', 1;

    IF @IDVariante IS NULL OR @IDVariante <= 0
        THROW 78702, 'Variante invalida.', 1;

    IF @Pagina IS NULL OR @Pagina < 1
       OR @TamanoPagina IS NULL
       OR @TamanoPagina NOT BETWEEN 1 AND 100
        THROW 78703, 'Paginacion invalida.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Existencias
        WHERE IDVariante = @IDVariante
    )
        THROW 78704, 'Variante no encontrada.', 1;

    DECLARE @Total BIGINT;

    SELECT @Total = COUNT_BIG(*)
    FROM dbo.MovimientosInventario
    WHERE IDVariante = @IDVariante;

    DECLARE @Offset BIGINT =
        (CONVERT(BIGINT, @Pagina) - 1) * @TamanoPagina;

    SELECT
        IDMovimientoInventario,
        IDVariante,
        IDUsuario,
        TipoMovimiento,
        CantidadFirmada,
        SaldoAnterior,
        SaldoPosterior,
        Motivo,
        FechaMovimiento
    FROM dbo.MovimientosInventario
    WHERE IDVariante = @IDVariante
    ORDER BY
        FechaMovimiento DESC,
        IDMovimientoInventario DESC
    OFFSET @Offset ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;

    SELECT
        @Pagina AS Pagina,
        @TamanoPagina AS TamanoPagina,
        @Total AS TotalRegistros,
        (@Total + @TamanoPagina - 1)
            / @TamanoPagina AS TotalPaginas;
END;
GO

-- ==========================================
-- PERMISOS Y VERSIONADO
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(
        N'dbo.SP_Inventario_RegistrarMovimiento', N'P'
    ) IS NULL
        THROW 78705,
            'Falta el procedimiento de movimientos.', 1;

    IF DATABASE_PRINCIPAL_ID(N'shopcart_api') IS NULL
        THROW 78706,
            'No existe shopcart_api.', 1;

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Inventario_RegistrarMovimiento
    TO [shopcart_api];

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Inventario_ConsultarExistencia
    TO [shopcart_api];

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Inventario_ListarKardex
    TO [shopcart_api];

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 48
    )
    BEGIN
        INSERT INTO dbo.SchemaMigrations (Numero, Nombre)
        VALUES (48, N'048_InventoryApiProcedures');
    END;

    COMMIT TRANSACTION;

    PRINT 'Migracion 048 aplicada correctamente.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
