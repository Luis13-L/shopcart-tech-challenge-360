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
        WHERE Numero = 41
    )
        THROW 76001,
            'Primero ejecute la migracion 041.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 42
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Catalogo_CrearCategoria', N'P'
        ) IS NOT NULL
        OR OBJECT_ID(
            N'dbo.SP_Catalogo_ListarCategorias', N'P'
        ) IS NOT NULL
        OR OBJECT_ID(
            N'dbo.SP_Catalogo_ActualizarCategoria', N'P'
        ) IS NOT NULL
        OR OBJECT_ID(
            N'dbo.SP_Catalogo_CambiarEstadoCategoria', N'P'
        ) IS NOT NULL
            THROW 76002,
                'Existen procedimientos sin migracion registrada.',
                1;

        -- =====================================
        -- 1. CREAR CATEGORIA
        -- =====================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_CrearCategoria
    @IDUsuarioActor INT,
    @Nombre NVARCHAR(120),
    @Descripcion NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Nombre = LTRIM(RTRIM(@Nombre));

    IF @Nombre IS NULL OR LEN(@Nombre) < 3
        THROW 76010, ''Nombre invalido.'', 1;

    DECLARE @IDCategoria INT;
    DECLARE @IDTexto VARCHAR(40);
    DECLARE @Despues NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios u
            INNER JOIN dbo.Roles r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = ''Administrador''
        )
            THROW 76011,
                ''Permisos insuficientes.'', 1;

        IF EXISTS (
            SELECT 1
            FROM dbo.Categorias
                WITH (UPDLOCK, HOLDLOCK)
            WHERE Nombre = @Nombre
        )
            THROW 76012,
                ''La categoria ya existe.'', 1;

        INSERT INTO dbo.Categorias (
            Nombre,
            Descripcion,
            Activa,
            FechaCreacion
        )
        VALUES (
            @Nombre,
            @Descripcion,
            1,
            SYSUTCDATETIME()
        );

        SET @IDCategoria =
            CONVERT(INT, SCOPE_IDENTITY());

        SET @IDTexto =
            CONVERT(VARCHAR(40), @IDCategoria);

        SELECT @Despues = (
            SELECT
                IDCategoria,
                Nombre,
                Descripcion,
                Activa
            FROM dbo.Categorias
            WHERE IDCategoria = @IDCategoria
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER,
                INCLUDE_NULL_VALUES
        );

        EXEC dbo.SP_Auditoria_RegistrarCambio
            @IDUsuario = @IDUsuarioActor,
            @Modulo = ''CATALOGO'',
            @Entidad = ''Categorias'',
            @IDEntidad = @IDTexto,
            @Accion = ''CREAR'',
            @ValoresAnteriores = NULL,
            @ValoresNuevos = @Despues;

        COMMIT TRANSACTION;

        SELECT
            IDCategoria,
            Nombre,
            Descripcion,
            Activa,
            FechaCreacion
        FROM dbo.Categorias
        WHERE IDCategoria = @IDCategoria;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
';

        -- =====================================
        -- 2. LISTAR CATEGORIAS
        -- =====================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_ListarCategorias
    @IDUsuarioActor INT = NULL,
    @IncluirInactivas BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @IncluirInactivas IS NULL
        THROW 76013,
            ''Filtro invalido.'', 1;

    -- El listado publico solo ve activas.
    -- Las inactivas son solo para Admin.
    IF @IncluirInactivas = 1
       AND NOT EXISTS (
           SELECT 1
           FROM dbo.Usuarios u
           INNER JOIN dbo.Roles r
               ON r.IDRol = u.IDRol
           WHERE u.IDUsuario = @IDUsuarioActor
             AND u.Activo = 1
             AND r.Nombre = ''Administrador''
       )
        THROW 76011,
            ''Permisos insuficientes.'', 1;

    SELECT
        IDCategoria,
        Nombre,
        Descripcion,
        Activa,
        FechaCreacion
    FROM dbo.Categorias
    WHERE @IncluirInactivas = 1
       OR Activa = 1
    ORDER BY Nombre, IDCategoria;
END;
';

        -- =====================================
        -- 3. ACTUALIZAR CATEGORIA
        -- =====================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_ActualizarCategoria
    @IDUsuarioActor INT,
    @IDCategoria INT,
    @Nombre NVARCHAR(120) = NULL,
    @Descripcion NVARCHAR(500) = NULL,
    @CambiarDescripcion BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IDCategoria IS NULL OR @IDCategoria <= 0
        THROW 76014,
            ''ID de categoria invalido.'', 1;

    IF @CambiarDescripcion IS NULL
        THROW 76015,
            ''Indicador invalido.'', 1;

    IF @Nombre IS NOT NULL
    BEGIN
        SET @Nombre = LTRIM(RTRIM(@Nombre));

        IF LEN(@Nombre) < 3
            THROW 76010,
                ''Nombre invalido.'', 1;
    END;

    IF @Nombre IS NULL
       AND @CambiarDescripcion = 0
        THROW 76016,
            ''No se proporcionaron cambios.'', 1;

    DECLARE @Antes NVARCHAR(MAX);
    DECLARE @Despues NVARCHAR(MAX);
    DECLARE @IDTexto VARCHAR(40) =
        CONVERT(VARCHAR(40), @IDCategoria);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios u
            INNER JOIN dbo.Roles r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = ''Administrador''
        )
            THROW 76011,
                ''Permisos insuficientes.'', 1;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Categorias
                WITH (UPDLOCK, HOLDLOCK)
            WHERE IDCategoria = @IDCategoria
        )
            THROW 76017,
                ''Categoria no encontrada.'', 1;

        IF @Nombre IS NOT NULL
           AND EXISTS (
               SELECT 1
               FROM dbo.Categorias
                   WITH (UPDLOCK, HOLDLOCK)
               WHERE Nombre = @Nombre
                 AND IDCategoria <> @IDCategoria
           )
            THROW 76012,
                ''Nombre duplicado.'', 1;

        SELECT @Antes = (
            SELECT
                IDCategoria,
                Nombre,
                Descripcion,
                Activa
            FROM dbo.Categorias
            WHERE IDCategoria = @IDCategoria
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER,
                INCLUDE_NULL_VALUES
        );

        UPDATE dbo.Categorias
        SET
            Nombre = COALESCE(
                @Nombre, Nombre
            ),
            Descripcion = CASE
                WHEN @CambiarDescripcion = 1
                    THEN @Descripcion
                ELSE Descripcion
            END
        WHERE IDCategoria = @IDCategoria;

        SELECT @Despues = (
            SELECT
                IDCategoria,
                Nombre,
                Descripcion,
                Activa
            FROM dbo.Categorias
            WHERE IDCategoria = @IDCategoria
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER,
                INCLUDE_NULL_VALUES
        );

        IF @Antes <> @Despues
        BEGIN
            EXEC dbo.SP_Auditoria_RegistrarCambio
                @IDUsuario = @IDUsuarioActor,
                @Modulo = ''CATALOGO'',
                @Entidad = ''Categorias'',
                @IDEntidad = @IDTexto,
                @Accion = ''ACTUALIZAR'',
                @ValoresAnteriores = @Antes,
                @ValoresNuevos = @Despues;
        END;

        COMMIT TRANSACTION;

        SELECT
            IDCategoria,
            Nombre,
            Descripcion,
            Activa,
            FechaCreacion
        FROM dbo.Categorias
        WHERE IDCategoria = @IDCategoria;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
';

        -- =====================================
        -- 4. ACTIVAR / DESACTIVAR CATEGORIA
        -- =====================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_CambiarEstadoCategoria
    @IDUsuarioActor INT,
    @IDCategoria INT,
    @Activa BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IDCategoria IS NULL OR @IDCategoria <= 0
        THROW 76014,
            ''ID de categoria invalido.'', 1;

    IF @Activa IS NULL
        THROW 76019,
            ''Estado invalido.'', 1;

    DECLARE @Anterior BIT;
    DECLARE @Antes NVARCHAR(MAX);
    DECLARE @Despues NVARCHAR(MAX);
    DECLARE @Accion VARCHAR(30);

    DECLARE @IDTexto VARCHAR(40) =
        CONVERT(VARCHAR(40), @IDCategoria);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios u
            INNER JOIN dbo.Roles r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = ''Administrador''
        )
            THROW 76011,
                ''Permisos insuficientes.'', 1;

        SELECT @Anterior = Activa
        FROM dbo.Categorias
            WITH (UPDLOCK, HOLDLOCK)
        WHERE IDCategoria = @IDCategoria;

        IF @Anterior IS NULL
            THROW 76017,
                ''Categoria no encontrada.'', 1;

        -- No ocultar productos activos
        -- al desactivar su categoria.
        IF @Activa = 0
           AND EXISTS (
               SELECT 1
               FROM dbo.Productos
               WHERE IDCategoria = @IDCategoria
                 AND Activo = 1
           )
            THROW 76018,
                ''La categoria tiene productos activos.'',
                1;

        IF @Anterior <> @Activa
        BEGIN
            SET @Antes = (
                SELECT @Anterior AS activa
                FOR JSON PATH,
                    WITHOUT_ARRAY_WRAPPER
            );

            SET @Despues = (
                SELECT @Activa AS activa
                FOR JSON PATH,
                    WITHOUT_ARRAY_WRAPPER
            );

            SET @Accion = CASE
                WHEN @Activa = 1 THEN ''ACTIVAR''
                ELSE ''DESACTIVAR''
            END;

            UPDATE dbo.Categorias
            SET Activa = @Activa
            WHERE IDCategoria = @IDCategoria;

            EXEC dbo.SP_Auditoria_RegistrarCambio
                @IDUsuario = @IDUsuarioActor,
                @Modulo = ''CATALOGO'',
                @Entidad = ''Categorias'',
                @IDEntidad = @IDTexto,
                @Accion = @Accion,
                @ValoresAnteriores = @Antes,
                @ValoresNuevos = @Despues;
        END;

        COMMIT TRANSACTION;

        SELECT
            IDCategoria,
            Nombre,
            Descripcion,
            Activa
        FROM dbo.Categorias
        WHERE IDCategoria = @IDCategoria;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
';

        -- =====================================
        -- 5. PERMISOS DE LA API
        -- =====================================

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_CrearCategoria
        TO [shopcart_api];

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_ListarCategorias
        TO [shopcart_api];

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_ActualizarCategoria
        TO [shopcart_api];

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_CambiarEstadoCategoria
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            42,
            N'042_CategoriesCrudProcedures'
        );

        PRINT 'Migracion 042 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Catalogo_CrearCategoria', N'P'
        ) IS NULL
        OR OBJECT_ID(
            N'dbo.SP_Catalogo_ListarCategorias', N'P'
        ) IS NULL
        OR OBJECT_ID(
            N'dbo.SP_Catalogo_ActualizarCategoria', N'P'
        ) IS NULL
        OR OBJECT_ID(
            N'dbo.SP_Catalogo_CambiarEstadoCategoria', N'P'
        ) IS NULL
            THROW 76003,
                'Migracion registrada con procedimientos faltantes.',
                1;

        PRINT 'Migracion 042 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
