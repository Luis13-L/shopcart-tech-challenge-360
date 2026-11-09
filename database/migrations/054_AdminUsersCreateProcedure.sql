USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ==========================================
-- MIGRACION 054
-- CREACION ADMINISTRATIVA DE USUARIOS
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 53
    )
        THROW 79800,
            'Primero ejecute la migracion 053.', 1;

    IF OBJECT_ID(
        N'dbo.SP_Auditoria_RegistrarCambio', N'P'
    ) IS NULL
        THROW 79801,
            'No existe el procedimiento de auditoria.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 54
    )
    BEGIN

        IF OBJECT_ID(
            N'dbo.SP_Usuarios_CrearAdministracion',
            N'P'
        ) IS NOT NULL
            THROW 79802,
                'El procedimiento ya existe sin migracion.',
                1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Usuarios_CrearAdministracion
    @IDUsuarioActor INT,
    @Correo NVARCHAR(254),
    @PasswordHash NVARCHAR(255),
    @Rol VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ======================================
    -- 1. VALIDAR PARAMETROS
    -- ======================================

    IF @IDUsuarioActor IS NULL
       OR @IDUsuarioActor <= 0
        THROW 79810,
            ''Usuario administrador invalido.'', 1;

    SET @Correo = LOWER(
        LTRIM(RTRIM(@Correo))
    );

    IF @Correo IS NULL
       OR LEN(@Correo) < 5
       OR LEN(@Correo) > 254
       OR @Correo NOT LIKE N''%_@_%._%''
       OR CHARINDEX(N'' '', @Correo) > 0
        THROW 79811,
            ''Correo electronico invalido.'', 1;

    IF @Rol IS NULL
       OR @Rol NOT IN (
           ''Cliente'',
           ''Operador'',
           ''Administrador''
       )
        THROW 79812,
            ''Rol de usuario invalido.'', 1;

    -- El backend genera un hash bcrypt
    -- con costo 12. SQL Server no recibe
    -- contrasenas en texto plano.

    IF @PasswordHash IS NULL
       OR LEN(@PasswordHash) <> 60
       OR LEFT(@PasswordHash, 4) <> N''$2b$''
       OR TRY_CONVERT(
           INT,
           SUBSTRING(@PasswordHash, 5, 2)
       ) NOT BETWEEN 12 AND 14
       OR SUBSTRING(@PasswordHash, 7, 1) <> N''$''
       OR PATINDEX(
           N''%[^A-Za-z0-9./]%'',
           SUBSTRING(@PasswordHash, 8, 53)
               COLLATE Latin1_General_100_BIN2
       ) > 0
        THROW 79813,
            ''Hash de contrasena invalido.'', 1;

    -- ======================================
    -- 2. VARIABLES
    -- ======================================

    DECLARE @IDRol INT;
    DECLARE @IDUsuarioNuevo INT;
    DECLARE @IDEntidad VARCHAR(40);
    DECLARE @DatosAuditoria NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ==================================
        -- 3. VALIDAR ADMINISTRADOR ACTIVO
        -- ==================================

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios AS u
            INNER JOIN dbo.Roles AS r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = ''Administrador''
        )
            THROW 79814,
                ''Administrador no autorizado.'', 1;

        -- ==================================
        -- 4. OBTENER ROL SOLICITADO
        -- ==================================

        SELECT
            @IDRol = IDRol
        FROM dbo.Roles
        WHERE Nombre = @Rol;

        IF @IDRol IS NULL
            THROW 79815,
                ''El rol solicitado no existe.'', 1;

        -- ==================================
        -- 5. PREVENIR CORREOS DUPLICADOS
        -- ==================================

        IF EXISTS (
            SELECT 1
            FROM dbo.Usuarios
                WITH (UPDLOCK, HOLDLOCK)
            WHERE Correo = @Correo
        )
            THROW 79816,
                ''El correo ya esta registrado.'', 1;

        -- ==================================
        -- 6. CREAR USUARIO ACTIVO
        -- ==================================

        INSERT INTO dbo.Usuarios (
            IDRol,
            Correo,
            PasswordHash,
            Activo,
            FechaCreacion
        )
        VALUES (
            @IDRol,
            @Correo,
            @PasswordHash,
            1,
            SYSUTCDATETIME()
        );

        SET @IDUsuarioNuevo =
            CONVERT(INT, SCOPE_IDENTITY());

        -- ==================================
        -- 7. REGISTRAR AUDITORIA
        -- ==================================

        SET @IDEntidad =
            CONVERT(VARCHAR(40), @IDUsuarioNuevo);

        SELECT @DatosAuditoria = (
            SELECT
                @IDUsuarioNuevo AS idUsuario,
                @Rol AS rol,
                CAST(1 AS BIT) AS activo
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.SP_Auditoria_RegistrarCambio
            @IDUsuario = @IDUsuarioActor,
            @Modulo = ''USUARIOS'',
            @Entidad = ''Usuarios'',
            @IDEntidad = @IDEntidad,
            @Accion = ''CREAR'',
            @ValoresAnteriores = NULL,
            @ValoresNuevos = @DatosAuditoria;

        COMMIT TRANSACTION;

        -- ==================================
        -- 8. DEVOLVER USUARIO CREADO
        -- ==================================

        SELECT
            u.IDUsuario,
            u.Correo,
            r.Nombre AS NombreRol,
            u.Activo,
            u.FechaCreacion
        FROM dbo.Usuarios AS u
        INNER JOIN dbo.Roles AS r
            ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuarioNuevo;

    END TRY
    BEGIN CATCH
        DECLARE @NumeroError INT =
            ERROR_NUMBER();

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        IF @NumeroError IN (2601, 2627)
            THROW 79816,
                ''El correo ya esta registrado.'', 1;

        THROW;
    END CATCH;
END;
';

        -- ======================================
        -- 9. CONCEDER PERMISOS A LA API
        -- ======================================

        IF DATABASE_PRINCIPAL_ID(
            N'shopcart_api'
        ) IS NULL
            THROW 79803,
                'No existe el usuario shopcart_api.', 1;

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Usuarios_CrearAdministracion
        TO [shopcart_api];

        -- ======================================
        -- 10. REGISTRAR MIGRACION
        -- ======================================

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            54,
            N'054_AdminUsersCreateProcedure'
        );

        PRINT
            'OK: Migracion 054 aplicada correctamente.';
    END
    ELSE
    BEGIN

        IF OBJECT_ID(
            N'dbo.SP_Usuarios_CrearAdministracion',
            N'P'
        ) IS NULL
            THROW 79804,
                'Migracion registrada sin procedimiento.',
                1;

        PRINT 'OK: Migracion 054 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
