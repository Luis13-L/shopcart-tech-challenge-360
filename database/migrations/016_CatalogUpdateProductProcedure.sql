
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
        WHERE Numero = 15
    )
        THROW 65200,
            'Primero ejecute la migracion 015.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 16
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Catalogo_ActualizarProducto', N'P'
        ) IS NOT NULL
            THROW 65201,
                'El procedimiento ya existe.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_ActualizarProducto
    @IDUsuarioActor INT,
    @IDProducto INT,
    @IDCategoria INT = NULL,
    @Nombre NVARCHAR(200) = NULL,
    @Descripcion NVARCHAR(2000) = NULL,
    @CambiarDescripcion BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Validar identificador
    IF @IDProducto IS NULL OR @IDProducto <= 0
        THROW 65202, ''Producto invalido.'', 1;

    -- Validar nombre cuando se proporciona
    IF @Nombre IS NOT NULL
    BEGIN
        SET @Nombre = LTRIM(RTRIM(@Nombre));

        IF LEN(@Nombre) < 3
            THROW 65203, ''Nombre invalido.'', 1;
    END;

    IF @CambiarDescripcion IS NULL
        THROW 65204,
            ''Indicador de descripcion invalido.'', 1;

    -- Requerir al menos un cambio
    IF @IDCategoria IS NULL
       AND @Nombre IS NULL
       AND @CambiarDescripcion = 0
        THROW 65205,
            ''No se proporcionaron cambios.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validar permisos vigentes del administrador
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios AS u
            INNER JOIN dbo.Roles AS r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = ''Administrador''
        )
            THROW 65206,
                ''Permisos insuficientes.'', 1;

        -- Bloquear el producto durante la actualizacion
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Productos WITH (UPDLOCK, HOLDLOCK)
            WHERE IDProducto = @IDProducto
              AND Activo = 1
        )
            THROW 65207,
                ''Producto inexistente o inactivo.'', 1;

        -- Validar categoria si se solicita cambiarla
        IF @IDCategoria IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
               FROM dbo.Categorias
               WHERE IDCategoria = @IDCategoria
                 AND Activa = 1
           )
            THROW 65208,
                ''Categoria inexistente o inactiva.'', 1;

        UPDATE dbo.Productos
        SET
            Nombre = COALESCE(@Nombre, Nombre),
            IDCategoria = COALESCE(
                @IDCategoria,
                IDCategoria
            ),
            Descripcion = CASE
                WHEN @CambiarDescripcion = 1
                    THEN @Descripcion
                ELSE Descripcion
            END
        WHERE IDProducto = @IDProducto
          AND Activo = 1;

        COMMIT TRANSACTION;

        -- Devolver producto actualizado
        SELECT
            IDProducto,
            IDCategoria,
            Nombre,
            Descripcion,
            Activo
        FROM dbo.Productos
        WHERE IDProducto = @IDProducto;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        -- Permitir ejecucion desde nuestra API
        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_ActualizarProducto
        TO [shopcart_api];

        -- Registrar migracion
        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            16,
            N'016_CatalogUpdateProductProcedure'
        );

        PRINT 'Migracion 016 aplicada correctamente.';
    END
    ELSE
    BEGIN
        PRINT 'Migracion 016 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
