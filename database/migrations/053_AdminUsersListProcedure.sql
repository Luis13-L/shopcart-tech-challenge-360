USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ==========================================
-- MIGRACION 053
-- CONSULTA ADMINISTRATIVA DE USUARIOS
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 52
    )
        THROW 79700,
            'Primero ejecute la migracion 052.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 53
    )
    BEGIN

        IF OBJECT_ID(
            N'dbo.SP_Usuarios_ListarAdministracion',
            N'P'
        ) IS NOT NULL
            THROW 79701,
                'El procedimiento ya existe sin migracion.',
                1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Usuarios_ListarAdministracion
    @IDUsuarioActor INT,
    @Pagina INT = 1,
    @TamanoPagina INT = 10,
    @Busqueda NVARCHAR(254) = NULL,
    @Rol VARCHAR(30) = NULL,
    @Activo BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- ======================================
    -- 1. VALIDAR ADMINISTRADOR
    -- ======================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios AS u
        INNER JOIN dbo.Roles AS r
            ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuarioActor
          AND u.Activo = 1
          AND r.Nombre = ''Administrador''
    )
        THROW 79710,
            ''Administrador no autorizado.'', 1;

    -- ======================================
    -- 2. VALIDAR PAGINACION
    -- ======================================

    IF @Pagina IS NULL
       OR @Pagina < 1
       OR @TamanoPagina IS NULL
       OR @TamanoPagina NOT BETWEEN 1 AND 100
        THROW 79711,
            ''Parametros de paginacion invalidos.'', 1;

    -- ======================================
    -- 3. NORMALIZAR FILTROS
    -- ======================================

    SET @Busqueda = NULLIF(
        LTRIM(RTRIM(@Busqueda)),
        N''''
    );

    SET @Rol = NULLIF(
        LTRIM(RTRIM(@Rol)),
        ''''
    );

    IF @Rol IS NOT NULL
       AND @Rol NOT IN (
           ''Cliente'',
           ''Operador'',
           ''Administrador''
       )
        THROW 79712,
            ''Rol de filtro invalido.'', 1;

    DECLARE @Offset BIGINT =
        (CONVERT(BIGINT, @Pagina) - 1)
        * @TamanoPagina;

    -- ======================================
    -- 4. LISTAR USUARIOS
    -- ======================================

    -- Nunca devolver PasswordHash,
    -- refresh tokens ni credenciales.

    SELECT
        u.IDUsuario,
        u.Correo,
        r.Nombre AS NombreRol,
        u.Activo,
        u.FechaCreacion
    FROM dbo.Usuarios AS u
    INNER JOIN dbo.Roles AS r
        ON r.IDRol = u.IDRol
    WHERE (
        @Busqueda IS NULL
        OR CHARINDEX(@Busqueda, u.Correo) > 0
    )
      AND (
        @Rol IS NULL
        OR r.Nombre = @Rol
    )
      AND (
        @Activo IS NULL
        OR u.Activo = @Activo
    )
    ORDER BY u.IDUsuario DESC
    OFFSET @Offset ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;

    -- ======================================
    -- 5. DEVOLVER TOTAL DE REGISTROS
    -- ======================================

    SELECT
        COUNT_BIG(*) AS Total
    FROM dbo.Usuarios AS u
    INNER JOIN dbo.Roles AS r
        ON r.IDRol = u.IDRol
    WHERE (
        @Busqueda IS NULL
        OR CHARINDEX(@Busqueda, u.Correo) > 0
    )
      AND (
        @Rol IS NULL
        OR r.Nombre = @Rol
    )
      AND (
        @Activo IS NULL
        OR u.Activo = @Activo
    );
END;
';

        -- API con permiso de ejecucion,
        -- sin acceso directo a tablas.

        IF DATABASE_PRINCIPAL_ID(
            N'shopcart_api'
        ) IS NULL
            THROW 79702,
                'No existe el usuario shopcart_api.', 1;

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Usuarios_ListarAdministracion
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            53,
            N'053_AdminUsersListProcedure'
        );

        PRINT
            'OK: Migracion 053 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Usuarios_ListarAdministracion',
            N'P'
        ) IS NULL
            THROW 79703,
                'Migracion registrada sin procedimiento.',
                1;

        PRINT 'OK: Migracion 053 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
