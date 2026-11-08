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
        WHERE Numero = 50
    )
        THROW 79500,
            'Primero ejecute la migracion 050.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 51
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Catalogo_RegistrarImagenProducto',
            N'P'
        ) IS NOT NULL
            THROW 79501,
                'El procedimiento de imagenes ya existe.', 1;

        IF OBJECT_ID(
            N'dbo.SP_Catalogo_ListarImagenesPrincipales',
            N'P'
        ) IS NOT NULL
            THROW 79502,
                'El procedimiento de consulta ya existe.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_RegistrarImagenProducto
    @IDUsuarioActor INT,
    @IDProducto INT,
    @URLImagen NVARCHAR(1000),
    @TextoAlternativo NVARCHAR(250) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuarioActor
          AND u.Activo = 1
          AND r.Nombre = ''Administrador''
    )
        THROW 79503, ''Permisos insuficientes.'', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Productos
        WHERE IDProducto = @IDProducto
          AND Activo = 1
    )
        THROW 79504, ''Producto no disponible.'', 1;

    IF @URLImagen IS NULL
       OR @URLImagen NOT LIKE
          N''/api/images/products/%.webp''
        THROW 79505, ''URL de imagen invalida.'', 1;

    INSERT INTO dbo.ImagenesProducto (
        IDProducto,
        URLImagen,
        TextoAlternativo,
        OrdenVisualizacion
    )
    VALUES (
        @IDProducto,
        @URLImagen,
        @TextoAlternativo,
        0
    );

    SELECT
        IDImagenProducto,
        IDProducto,
        URLImagen,
        TextoAlternativo
    FROM dbo.ImagenesProducto
    WHERE IDImagenProducto = SCOPE_IDENTITY();
END;
';

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_ListarImagenesPrincipales
    @IdsJson NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    IF @IdsJson IS NULL
       OR ISJSON(@IdsJson) <> 1
        THROW 79506, ''Lista de IDs invalida.'', 1;

    ;WITH ImagenesOrdenadas AS (
        SELECT
            i.IDProducto,
            i.URLImagen,
            i.TextoAlternativo,
            ROW_NUMBER() OVER (
                PARTITION BY i.IDProducto
                ORDER BY
                    i.OrdenVisualizacion,
                    i.IDImagenProducto
            ) AS Numero
        FROM dbo.ImagenesProducto i
        INNER JOIN dbo.Productos p
            ON p.IDProducto = i.IDProducto
           AND p.Activo = 1
        INNER JOIN OPENJSON(@IdsJson) ids
            ON TRY_CONVERT(INT, ids.[value])
                = i.IDProducto
    )
    SELECT
        IDProducto,
        URLImagen,
        TextoAlternativo
    FROM ImagenesOrdenadas
    WHERE Numero = 1;
END;
';

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_RegistrarImagenProducto
        TO [shopcart_api];

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_ListarImagenesPrincipales
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            51,
            N'051_CatalogProductImages'
        );
    END;

    COMMIT TRANSACTION;

    PRINT 'Migracion 051 verificada correctamente.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
