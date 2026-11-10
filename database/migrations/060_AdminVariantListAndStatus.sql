USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Migracion 060: listado y estado de variantes.
-- No cambia precios, existencias, reservas ni kardex.
BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.SchemaMigrations WHERE Numero = 59)
        THROW 80400, 'Primero ejecute la migracion 059.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 60
    )
    BEGIN
        IF OBJECT_ID(N'dbo.SP_Catalogo_ListarVariantesAdmin', N'P') IS NOT NULL
           OR OBJECT_ID(N'dbo.SP_Catalogo_CambiarEstadoVariante', N'P') IS NOT NULL
            THROW 80401, 'Existen procedimientos sin migracion registrada.', 1;

        IF OBJECT_ID(N'dbo.SP_Auditoria_RegistrarCambio', N'P') IS NULL
            THROW 80402, 'Falta procedimiento de auditoria.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_ListarVariantesAdmin
    @IDUsuarioActor INT,
    @IDProducto INT,
    @Pagina INT = 1,
    @TamanoPagina INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.Usuarios AS u
        INNER JOIN dbo.Roles AS r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuarioActor
          AND u.Activo = 1
          AND r.Nombre = ''Administrador''
    ) THROW 80420, ''Administrador no autorizado.'', 1;

    IF @IDProducto IS NULL OR @IDProducto <= 0
        THROW 80421, ''ID de producto invalido.'', 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.Productos
        WHERE IDProducto = @IDProducto
    ) THROW 80423, ''Producto no encontrado.'', 1;

    IF @Pagina IS NULL OR @Pagina NOT BETWEEN 1 AND 10000
       OR @TamanoPagina IS NULL OR @TamanoPagina NOT BETWEEN 1 AND 50
        THROW 80422, ''Paginacion invalida.'', 1;

    DECLARE @Offset BIGINT =
        (CONVERT(BIGINT, @Pagina) - 1) * @TamanoPagina;

    -- Resultado 0: total de variantes del producto.
    SELECT COUNT_BIG(*) AS Total
    FROM dbo.Variantes
    WHERE IDProducto = @IDProducto;

    -- Resultado 1: variantes, precio, stock y atributos.
    SELECT
        v.IDVariante,
        v.IDProducto,
        v.SKU,
        CONVERT(VARCHAR(32), v.PrecioActual) AS PrecioActual,
        v.Activa,
        v.FechaCreacion,
        ISNULL(e.CantidadFisica, 0) AS CantidadFisica,
        (SELECT av.Nombre AS nombre, av.Valor AS valor
         FROM dbo.AtributosVariante AS av
         WHERE av.IDVariante = v.IDVariante
         ORDER BY av.Nombre, av.IDAtributoVariante
         FOR JSON PATH) AS AtributosJson
    FROM dbo.Variantes AS v
    LEFT JOIN dbo.Existencias AS e ON e.IDVariante = v.IDVariante
    WHERE v.IDProducto = @IDProducto
    ORDER BY v.IDVariante ASC
    OFFSET @Offset ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END;';

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_CambiarEstadoVariante
    @IDUsuarioActor INT,
    @IDVariante INT,
    @Activa BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IDVariante IS NULL OR @IDVariante <= 0
        THROW 80411, ''ID de variante invalido.'', 1;

    IF @Activa IS NULL
        THROW 80414, ''Estado de variante invalido.'', 1;

    DECLARE @IDProducto INT;
    DECLARE @IDCategoria INT;
    DECLARE @ProductoActivo BIT;
    DECLARE @CategoriaActiva BIT;
    DECLARE @EstadoAnterior BIT;
    DECLARE @SKU NVARCHAR(64);
    DECLARE @Antes NVARCHAR(MAX);
    DECLARE @Despues NVARCHAR(MAX);
    DECLARE @Accion VARCHAR(30);
    DECLARE @Cambio BIT = 0;
    DECLARE @IDTexto VARCHAR(40) = CONVERT(VARCHAR(40), @IDVariante);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1 FROM dbo.Usuarios AS u
            INNER JOIN dbo.Roles AS r ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = ''Administrador''
        ) THROW 80410, ''Administrador no autorizado.'', 1;

        -- Descubrir categoria antes de adquirir bloqueos.
        SELECT
            @IDProducto = v.IDProducto,
            @IDCategoria = p.IDCategoria
        FROM dbo.Variantes AS v
        INNER JOIN dbo.Productos AS p ON p.IDProducto = v.IDProducto
        WHERE v.IDVariante = @IDVariante;

        IF @IDProducto IS NULL
            THROW 80412, ''Variante no encontrada.'', 1;

        -- Mismo orden de bloqueo categoria -> producto -> variante
        -- que en la reactivacion de productos de la migracion 058.
        SELECT @CategoriaActiva = c.Activa
        FROM dbo.Categorias AS c WITH (UPDLOCK, HOLDLOCK)
        WHERE c.IDCategoria = @IDCategoria;

        SELECT @ProductoActivo = p.Activo
        FROM dbo.Productos AS p WITH (UPDLOCK, HOLDLOCK)
        WHERE p.IDProducto = @IDProducto
          AND p.IDCategoria = @IDCategoria;

        IF @ProductoActivo IS NULL
            THROW 80415, ''El producto cambio durante la operacion.'', 1;

        SELECT @EstadoAnterior = v.Activa, @SKU = v.SKU
        FROM dbo.Variantes AS v WITH (UPDLOCK, HOLDLOCK)
        WHERE v.IDVariante = @IDVariante
          AND v.IDProducto = @IDProducto;

        IF @EstadoAnterior IS NULL
            THROW 80412, ''Variante no encontrada.'', 1;

        -- No activar una variante de producto o categoria inactivos.
        IF @Activa = 1 AND (
            @ProductoActivo <> 1 OR @CategoriaActiva <> 1
        ) THROW 80413, ''Producto o categoria inactiva.'', 1;

        IF @EstadoAnterior <> @Activa
        BEGIN
            SELECT @Antes = (
                SELECT IDVariante, IDProducto, SKU, Activa
                FROM dbo.Variantes
                WHERE IDVariante = @IDVariante
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            UPDATE dbo.Variantes
            SET Activa = @Activa
            WHERE IDVariante = @IDVariante
              AND Activa = @EstadoAnterior;

            IF @@ROWCOUNT <> 1
                THROW 80415, ''Conflicto al actualizar variante.'', 1;

            SELECT @Despues = (
                SELECT IDVariante, IDProducto, SKU, Activa
                FROM dbo.Variantes
                WHERE IDVariante = @IDVariante
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            SET @Accion = CASE WHEN @Activa = 1
                              THEN ''ACTIVAR'' ELSE ''DESACTIVAR'' END;

            EXEC dbo.SP_Auditoria_RegistrarCambio
                @IDUsuario = @IDUsuarioActor,
                @Modulo = ''CATALOGO'',
                @Entidad = ''Variantes'',
                @IDEntidad = @IDTexto,
                @Accion = @Accion,
                @ValoresAnteriores = @Antes,
                @ValoresNuevos = @Despues;

            SET @Cambio = 1;
        END;

        COMMIT TRANSACTION;

        SELECT
            @IDVariante AS IDVariante,
            @IDProducto AS IDProducto,
            @SKU AS SKU,
            @Activa AS Activa,
            @Cambio AS Actualizado;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

        IF DATABASE_PRINCIPAL_ID(N'shopcart_api') IS NULL
            THROW 80403, 'No existe el usuario shopcart_api.', 1;

        GRANT EXECUTE ON OBJECT::dbo.SP_Catalogo_ListarVariantesAdmin
            TO [shopcart_api];
        GRANT EXECUTE ON OBJECT::dbo.SP_Catalogo_CambiarEstadoVariante
            TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (Numero, Nombre)
        VALUES (60, N'060_AdminVariantListAndStatus');

        PRINT 'OK: Migracion 060 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(N'dbo.SP_Catalogo_ListarVariantesAdmin', N'P') IS NULL
           OR OBJECT_ID(N'dbo.SP_Catalogo_CambiarEstadoVariante', N'P') IS NULL
            THROW 80404, 'Migracion registrada con procedimientos faltantes.', 1;
        PRINT 'OK: Migracion 060 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
