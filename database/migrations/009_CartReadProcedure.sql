
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
        WHERE Numero = 8
    )
        THROW 60001,
            'Primero ejecute la migracion 008.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 9
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Carrito_ObtenerDetalle', N'P'
        ) IS NOT NULL
            THROW 60002,
                'Procedimiento ya existente.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Carrito_ObtenerDetalle
    @IDCarrito BIGINT,
    @IDUsuario INT = NULL,
    @TokenInvitadoHash BINARY(32) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IDCarrito IS NULL OR @IDCarrito <= 0
        THROW 60003, ''Carrito invalido.'', 1;

    IF (
        @IDUsuario IS NULL
        AND @TokenInvitadoHash IS NULL
    ) OR (
        @IDUsuario IS NOT NULL
        AND @TokenInvitadoHash IS NOT NULL
    )
        THROW 60004,
            ''Debe indicar un unico propietario.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validar propiedad y estado
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Carritos AS c WITH (HOLDLOCK)
            WHERE c.IDCarrito = @IDCarrito
              AND c.Estado = ''ACTIVO''
              AND (
                  (
                      @IDUsuario IS NOT NULL
                      AND c.IDUsuario = @IDUsuario
                      AND EXISTS (
                          SELECT 1
                          FROM dbo.Usuarios u
                          INNER JOIN dbo.Roles r
                              ON r.IDRol = u.IDRol
                          WHERE u.IDUsuario = @IDUsuario
                            AND u.Activo = 1
                            AND r.Nombre = ''Cliente''
                      )
                  )
                  OR (
                      @TokenInvitadoHash IS NOT NULL
                      AND c.TokenInvitadoHash =
                          @TokenInvitadoHash
                  )
              )
        )
            THROW 60005,
                ''Carrito inexistente o acceso denegado.'', 1;

        -- Materializar las lineas para obtener
        -- detalle y resumen consistentes.
        CREATE TABLE #Lineas (
            IDDetalleCarrito BIGINT NOT NULL,
            IDVariante INT NOT NULL,
            SKU NVARCHAR(64) NOT NULL,
            NombreProducto NVARCHAR(200) NOT NULL,
            PrecioUnitario DECIMAL(19,2) NOT NULL,
            Cantidad INT NOT NULL,
            ImporteLinea DECIMAL(19,2) NOT NULL
        );

        INSERT INTO #Lineas (
            IDDetalleCarrito,
            IDVariante,
            SKU,
            NombreProducto,
            PrecioUnitario,
            Cantidad,
            ImporteLinea
        )
        SELECT
            d.IDDetalleCarrito,
            d.IDVariante,
            v.SKU,
            p.Nombre,
            v.PrecioActual,
            d.Cantidad,
            CAST(
                v.PrecioActual *
                CONVERT(DECIMAL(18,0), d.Cantidad)
                AS DECIMAL(19,2)
            )
        FROM dbo.DetallesCarrito d
        INNER JOIN dbo.Variantes v
            ON v.IDVariante = d.IDVariante
        INNER JOIN dbo.Productos p
            ON p.IDProducto = v.IDProducto
        WHERE d.IDCarrito = @IDCarrito;

        -- Resultado 1: Resumen del carrito
        SELECT
            @IDCarrito AS IDCarrito,
            COUNT(*) AS CantidadLineas,
            ISNULL(SUM(ImporteLinea), 0)
                AS Subtotal,
            CAST(0 AS DECIMAL(19,2))
                AS Descuento,
            ISNULL(SUM(ImporteLinea), 0)
                AS Total
        FROM #Lineas;

        -- Resultado 2: Productos del carrito
        SELECT
            IDDetalleCarrito,
            IDVariante,
            SKU,
            NombreProducto,
            PrecioUnitario,
            Cantidad,
            ImporteLinea
        FROM #Lineas
        ORDER BY IDDetalleCarrito;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        INSERT INTO dbo.SchemaMigrations (
            Numero, Nombre
        )
        VALUES (
            9, N'009_CartReadProcedure'
        );
    END
    ELSE IF OBJECT_ID(
        N'dbo.SP_Carrito_ObtenerDetalle', N'P'
    ) IS NULL
        THROW 60006,
            'Migracion registrada sin procedimiento.', 1;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
