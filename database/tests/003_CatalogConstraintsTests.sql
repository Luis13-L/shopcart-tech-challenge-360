
USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

DECLARE @IDCategoria INT;
DECLARE @IDProducto INT;
DECLARE @SKU NVARCHAR(64);
DECLARE @Sufijo NVARCHAR(36) =
    CONVERT(NVARCHAR(36), NEWID());

DECLARE @Resultados TABLE (
    Prueba NVARCHAR(100),
    Resultado VARCHAR(15),
    CodigoError INT
);

BEGIN TRY
    BEGIN TRANSACTION;

    -- Datos temporales para pruebas
    INSERT INTO dbo.Categorias (Nombre)
    VALUES (N'QA-' + @Sufijo);

    SET @IDCategoria = SCOPE_IDENTITY();

    INSERT INTO dbo.Productos (
        IDCategoria, Nombre
    )
    VALUES (
        @IDCategoria, N'Producto de prueba'
    );

    SET @IDProducto = SCOPE_IDENTITY();

    SET @SKU = N'SKU-QA-' + @Sufijo;

    INSERT INTO dbo.Variantes (
        IDProducto, SKU, PrecioActual
    )
    VALUES (
        @IDProducto, @SKU, 150.00
    );

    -- PRUEBA 1: SKU DUPLICADO
    BEGIN TRY
        INSERT INTO dbo.Variantes (
            IDProducto, SKU, PrecioActual
        )
        VALUES (
            @IDProducto, @SKU, 200.00
        );

        INSERT INTO @Resultados
        VALUES ('SKU duplicado', 'FALLO', NULL);
    END TRY
    BEGIN CATCH
        INSERT INTO @Resultados
        VALUES (
            'SKU duplicado',
            CASE
                WHEN ERROR_NUMBER() IN (2601, 2627)
                THEN 'APROBADO'
                ELSE 'REVISAR'
            END,
            ERROR_NUMBER()
        );
    END CATCH;

    -- PRUEBA 2: PRECIO NEGATIVO
    BEGIN TRY
        INSERT INTO dbo.Variantes (
            IDProducto, SKU, PrecioActual
        )
        VALUES (
            @IDProducto,
            N'NEG-' + @Sufijo,
            -50.00
        );

        INSERT INTO @Resultados
        VALUES ('Precio negativo', 'FALLO', NULL);
    END TRY
    BEGIN CATCH
        INSERT INTO @Resultados
        VALUES (
            'Precio negativo',
            CASE
                WHEN ERROR_NUMBER() = 547
                THEN 'APROBADO'
                ELSE 'REVISAR'
            END,
            ERROR_NUMBER()
        );
    END CATCH;

    -- PRUEBA 3: CATEGORIA INEXISTENTE
    BEGIN TRY
        INSERT INTO dbo.Productos (
            IDCategoria, Nombre
        )
        VALUES (
            -1, N'Producto sin categoria'
        );

        INSERT INTO @Resultados
        VALUES ('Categoria inexistente', 'FALLO', NULL);
    END TRY
    BEGIN CATCH
        INSERT INTO @Resultados
        VALUES (
            'Categoria inexistente',
            CASE
                WHEN ERROR_NUMBER() = 547
                THEN 'APROBADO'
                ELSE 'REVISAR'
            END,
            ERROR_NUMBER()
        );
    END CATCH;

    -- Deshacer los datos de prueba
    ROLLBACK TRANSACTION;

    SELECT *
    FROM @Resultados;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
