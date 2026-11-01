USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 39
)
    THROW 74001,
        'Primero ejecute la migracion 039.', 1;
GO

-- ==========================================
-- 1. CREAR PRODUCTO Y AUDITAR
-- Conserva correccion IDENTITY de migracion 015
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_CrearProducto
    @IDUsuarioActor INT,
    @IDCategoria INT,
    @Nombre NVARCHAR(200),
    @Descripcion NVARCHAR(2000) = NULL,
    @SKU NVARCHAR(64),
    @PrecioActual DECIMAL(19,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- AUDIT_V40_CrearProducto

    SET @Nombre = LTRIM(RTRIM(@Nombre));
    SET @SKU = UPPER(LTRIM(RTRIM(@SKU)));

    IF @Nombre IS NULL OR LEN(@Nombre) < 3
        THROW 65104,
            'Nombre de producto invalido.', 1;

    IF @SKU IS NULL OR LEN(@SKU) < 3
        THROW 65105,
            'SKU invalido.', 1;

    IF @PrecioActual IS NULL OR @PrecioActual <= 0
        THROW 65106,
            'Precio invalido.', 1;

    DECLARE @IDProducto INT;
    DECLARE @IDVariante INT;
    DECLARE @IDProductoTexto VARCHAR(40);
    DECLARE @IDVarianteTexto VARCHAR(40);
    DECLARE @NuevoProducto NVARCHAR(MAX);
    DECLARE @NuevaVariante NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios u
            INNER JOIN dbo.Roles r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = 'Administrador'
        )
            THROW 65107,
                'Usuario sin permisos administrativos.',
                1;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Categorias
            WHERE IDCategoria = @IDCategoria
              AND Activa = 1
        )
            THROW 65108,
                'Categoria inexistente o inactiva.',
                1;

        IF EXISTS (
            SELECT 1
            FROM dbo.Variantes WITH (
                UPDLOCK, HOLDLOCK
            )
            WHERE SKU = @SKU
        )
            THROW 65109,
                'El SKU ya existe.', 1;

        INSERT INTO dbo.Productos (
            IDCategoria,
            Nombre,
            Descripcion,
            Activo,
            FechaCreacion
        )
        VALUES (
            @IDCategoria,
            @Nombre,
            @Descripcion,
            1,
            SYSUTCDATETIME()
        );

        SET @IDProducto =
            CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.Variantes (
            IDProducto,
            SKU,
            PrecioActual,
            Activa,
            FechaCreacion
        )
        VALUES (
            @IDProducto,
            @SKU,
            @PrecioActual,
            1,
            SYSUTCDATETIME()
        );

        SET @IDVariante =
            CONVERT(INT, SCOPE_IDENTITY());

        SET @IDProductoTexto =
            CONVERT(VARCHAR(40), @IDProducto);

        SET @IDVarianteTexto =
            CONVERT(VARCHAR(40), @IDVariante);

        SELECT @NuevoProducto = (
            SELECT
                IDProducto,
                IDCategoria,
                Nombre,
                Descripcion,
                Activo
            FROM dbo.Productos
            WHERE IDProducto = @IDProducto
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER,
                INCLUDE_NULL_VALUES
        );

        SELECT @NuevaVariante = (
            SELECT
                IDVariante,
                IDProducto,
                SKU,
                PrecioActual,
                Activa
            FROM dbo.Variantes
            WHERE IDVariante = @IDVariante
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.SP_Auditoria_RegistrarCambio
            @IDUsuario = @IDUsuarioActor,
            @Modulo = 'CATALOGO',
            @Entidad = 'Productos',
            @IDEntidad = @IDProductoTexto,
            @Accion = 'CREAR',
            @ValoresAnteriores = NULL,
            @ValoresNuevos = @NuevoProducto;

        EXEC dbo.SP_Auditoria_RegistrarCambio
            @IDUsuario = @IDUsuarioActor,
            @Modulo = 'CATALOGO',
            @Entidad = 'Variantes',
            @IDEntidad = @IDVarianteTexto,
            @Accion = 'CREAR',
            @ValoresAnteriores = NULL,
            @ValoresNuevos = @NuevaVariante;

        COMMIT TRANSACTION;

        SELECT
            @IDProducto AS IDProducto,
            @IDVariante AS IDVariante,
            @Nombre AS Nombre,
            @SKU AS SKU,
            @PrecioActual AS PrecioActual;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO

-- ==========================================
-- 2. ACTUALIZAR PRODUCTO Y AUDITAR
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_ActualizarProducto
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

    -- AUDIT_V40_ActualizarProducto

    IF @IDProducto IS NULL OR @IDProducto <= 0
        THROW 65202, 'Producto invalido.', 1;

    IF @Nombre IS NOT NULL
    BEGIN
        SET @Nombre = LTRIM(RTRIM(@Nombre));

        IF LEN(@Nombre) < 3
            THROW 65203, 'Nombre invalido.', 1;
    END;

    IF @CambiarDescripcion IS NULL
        THROW 65204,
            'Indicador de descripcion invalido.', 1;

    IF @IDCategoria IS NULL
       AND @Nombre IS NULL
       AND @CambiarDescripcion = 0
        THROW 65205,
            'No se proporcionaron cambios.', 1;

    DECLARE @Antes NVARCHAR(MAX);
    DECLARE @Despues NVARCHAR(MAX);
    DECLARE @IDProductoTexto VARCHAR(40) =
        CONVERT(VARCHAR(40), @IDProducto);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios u
            INNER JOIN dbo.Roles r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = 'Administrador'
        )
            THROW 65206,
                'Permisos insuficientes.', 1;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Productos WITH (
                UPDLOCK, HOLDLOCK
            )
            WHERE IDProducto = @IDProducto
              AND Activo = 1
        )
            THROW 65207,
                'Producto inexistente o inactivo.',
                1;

        IF @IDCategoria IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
               FROM dbo.Categorias
               WHERE IDCategoria = @IDCategoria
                 AND Activa = 1
           )
            THROW 65208,
                'Categoria inexistente o inactiva.',
                1;

        SELECT @Antes = (
            SELECT
                IDProducto,
                IDCategoria,
                Nombre,
                Descripcion,
                Activo
            FROM dbo.Productos
            WHERE IDProducto = @IDProducto
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER,
                INCLUDE_NULL_VALUES
        );

        UPDATE dbo.Productos
        SET
            Nombre = COALESCE(
                @Nombre, Nombre
            ),
            IDCategoria = COALESCE(
                @IDCategoria, IDCategoria
            ),
            Descripcion = CASE
                WHEN @CambiarDescripcion = 1
                    THEN @Descripcion
                ELSE Descripcion
            END
        WHERE IDProducto = @IDProducto
          AND Activo = 1;

        SELECT @Despues = (
            SELECT
                IDProducto,
                IDCategoria,
                Nombre,
                Descripcion,
                Activo
            FROM dbo.Productos
            WHERE IDProducto = @IDProducto
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER,
                INCLUDE_NULL_VALUES
        );

        IF @Antes <> @Despues
        BEGIN
            EXEC dbo.SP_Auditoria_RegistrarCambio
                @IDUsuario = @IDUsuarioActor,
                @Modulo = 'CATALOGO',
                @Entidad = 'Productos',
                @IDEntidad = @IDProductoTexto,
                @Accion = 'ACTUALIZAR',
                @ValoresAnteriores = @Antes,
                @ValoresNuevos = @Despues;
        END;

        COMMIT TRANSACTION;

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
GO

-- ==========================================
-- 3. DESACTIVAR PRODUCTO Y AUDITAR
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_DesactivarProducto
    @IDUsuarioActor INT,
    @IDProducto INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- AUDIT_V40_DesactivarProducto

    IF @IDProducto IS NULL OR @IDProducto <= 0
        THROW 65302,
            'ID de producto invalido.', 1;

    DECLARE @Antes NVARCHAR(MAX);
    DECLARE @Despues NVARCHAR(MAX);
    DECLARE @VariantesDesactivadas INT;
    DECLARE @IDProductoTexto VARCHAR(40) =
        CONVERT(VARCHAR(40), @IDProducto);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios u
            INNER JOIN dbo.Roles r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = 'Administrador'
        )
            THROW 65303,
                'Permisos administrativos insuficientes.',
                1;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Productos WITH (
                UPDLOCK, HOLDLOCK
            )
            WHERE IDProducto = @IDProducto
        )
            THROW 65304,
                'Producto no encontrado.', 1;

        -- Guardar estado anterior,
        -- incluyendo las variantes.
        SELECT @Antes = (
            SELECT
                p.IDProducto,
                p.Nombre,
                p.Activo,
                JSON_QUERY((
                    SELECT
                        v.IDVariante,
                        v.Activa
                    FROM dbo.Variantes v
                    WHERE v.IDProducto = p.IDProducto
                    ORDER BY v.IDVariante
                    FOR JSON PATH
                )) AS variantes
            FROM dbo.Productos p
            WHERE p.IDProducto = @IDProducto
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER
        );

        UPDATE dbo.Productos
        SET Activo = 0
        WHERE IDProducto = @IDProducto
          AND Activo = 1;

        UPDATE dbo.Variantes
        SET Activa = 0
        WHERE IDProducto = @IDProducto
          AND Activa = 1;

        SET @VariantesDesactivadas = @@ROWCOUNT;

        -- Guardar estado posterior.
        SELECT @Despues = (
            SELECT
                p.IDProducto,
                p.Nombre,
                p.Activo,
                JSON_QUERY((
                    SELECT
                        v.IDVariante,
                        v.Activa
                    FROM dbo.Variantes v
                    WHERE v.IDProducto = p.IDProducto
                    ORDER BY v.IDVariante
                    FOR JSON PATH
                )) AS variantes
            FROM dbo.Productos p
            WHERE p.IDProducto = @IDProducto
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER
        );

        -- Si ya estaba desactivado,
        -- no generar auditoria duplicada.
        IF @Antes <> @Despues
        BEGIN
            EXEC dbo.SP_Auditoria_RegistrarCambio
                @IDUsuario = @IDUsuarioActor,
                @Modulo = 'CATALOGO',
                @Entidad = 'Productos',
                @IDEntidad = @IDProductoTexto,
                @Accion = 'DESACTIVAR',
                @ValoresAnteriores = @Antes,
                @ValoresNuevos = @Despues;
        END;

        COMMIT TRANSACTION;

        SELECT
            IDProducto,
            Nombre,
            Activo,
            @VariantesDesactivadas
                AS VariantesDesactivadas
        FROM dbo.Productos
        WHERE IDProducto = @IDProducto;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO

-- ==========================================
-- 4. VERIFICAR VERSIONES, PERMISOS Y REGISTRO
-- ==========================================

SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_DEFINITION(
        OBJECT_ID('dbo.SP_Catalogo_CrearProducto')
    ) NOT LIKE '%AUDIT_V40_CrearProducto%'
       OR OBJECT_DEFINITION(
        OBJECT_ID('dbo.SP_Catalogo_ActualizarProducto')
    ) NOT LIKE '%AUDIT_V40_ActualizarProducto%'
       OR OBJECT_DEFINITION(
        OBJECT_ID('dbo.SP_Catalogo_DesactivarProducto')
    ) NOT LIKE '%AUDIT_V40_DesactivarProducto%'
        THROW 74002,
            'No se actualizaron todos los procedimientos.',
            1;

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Catalogo_CrearProducto
    TO [shopcart_api];

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Catalogo_ActualizarProducto
    TO [shopcart_api];

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Catalogo_DesactivarProducto
    TO [shopcart_api];

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 40
    )
    BEGIN
        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            40,
            N'040_AuditCatalogProcedures'
        );
    END;

    COMMIT TRANSACTION;

    PRINT 'Migracion 040 aplicada correctamente.';

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
