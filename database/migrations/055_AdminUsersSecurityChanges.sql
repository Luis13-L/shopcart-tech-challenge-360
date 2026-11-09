USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ==========================================
-- MIGRACION 055
-- CAMBIO DE ROL Y ESTADO DE USUARIOS
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. VALIDAR DEPENDENCIAS

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 54
    )
        THROW 79900,
            'Primero ejecute la migracion 054.', 1;

    IF OBJECT_ID(
        N'dbo.SP_Auditoria_RegistrarCambio', N'P'
    ) IS NULL
        THROW 79901,
            'No existe el procedimiento de auditoria.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 55
    )
    BEGIN

        IF OBJECT_ID(
            N'dbo.SP_Usuarios_ActualizarSeguridadAdministracion',
            N'P'
        ) IS NOT NULL
            THROW 79902,
                'El procedimiento ya existe sin migracion.', 1;

        -- ======================================
        -- 2. CREAR PROCEDIMIENTO
        -- ======================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE
dbo.SP_Usuarios_ActualizarSeguridadAdministracion
    @IDUsuarioActor INT,
    @IDUsuarioObjetivo INT,
    @Rol VARCHAR(30) = NULL,
    @Activo BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ======================================
    -- VALIDAR PARAMETROS
    -- ======================================

    IF @IDUsuarioActor IS NULL
       OR @IDUsuarioActor <= 0
        THROW 79910,
            ''Administrador invalido.'', 1;

    IF @IDUsuarioObjetivo IS NULL
       OR @IDUsuarioObjetivo <= 0
        THROW 79911,
            ''Usuario objetivo invalido.'', 1;

    -- Solo una operacion por solicitud.

    IF (
        @Rol IS NULL AND @Activo IS NULL
    ) OR (
        @Rol IS NOT NULL AND @Activo IS NOT NULL
    )
        THROW 79912,
            ''Indique solo rol o estado.'', 1;

    IF @Rol IS NOT NULL
       AND @Rol NOT IN (
           ''Cliente'',
           ''Operador'',
           ''Administrador''
       )
        THROW 79913,
            ''Rol solicitado invalido.'', 1;

    -- ======================================
    -- VARIABLES
    -- ======================================

    DECLARE @IDRolAdmin INT;
    DECLARE @IDRolAnterior INT;
    DECLARE @IDRolNuevo INT;

    DECLARE @RolAnterior VARCHAR(30);
    DECLARE @RolNuevo VARCHAR(30);

    DECLARE @ActivoAnterior BIT;
    DECLARE @ActivoNuevo BIT;

    DECLARE @TotalAdministradores BIGINT;

    DECLARE @IDEntidad VARCHAR(40);
    DECLARE @Accion VARCHAR(30);

    DECLARE @ValoresAnteriores NVARCHAR(MAX);
    DECLARE @ValoresNuevos NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ==================================
        -- 1. BLOQUEO DE SEGURIDAD
        -- ==================================

        -- Serializar cambios de permisos
        -- realizados por estos procedimientos.

        SELECT
            @IDRolAdmin = IDRol
        FROM dbo.Roles WITH (UPDLOCK, HOLDLOCK)
        WHERE Nombre = ''Administrador'';

        IF @IDRolAdmin IS NULL
            THROW 79918,
                ''No existe el rol Administrador.'', 1;

        -- ==================================
        -- 2. VALIDAR ACTOR
        -- ==================================

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios WITH (UPDLOCK, HOLDLOCK)
            WHERE IDUsuario = @IDUsuarioActor
              AND IDRol = @IDRolAdmin
              AND Activo = 1
        )
            THROW 79914,
                ''Administrador no autorizado.'', 1;

        -- ==================================
        -- 3. IMPEDIR CAMBIOS SOBRE SI MISMO
        -- ==================================

        IF @IDUsuarioActor = @IDUsuarioObjetivo
            THROW 79915,
                ''No puede modificar su propio rol o estado.'',
                1;

        -- ==================================
        -- 4. OBTENER USUARIO OBJETIVO
        -- ==================================

        SELECT
            @IDRolAnterior = IDRol,
            @ActivoAnterior = Activo
        FROM dbo.Usuarios WITH (UPDLOCK, HOLDLOCK)
        WHERE IDUsuario = @IDUsuarioObjetivo;

        IF @IDRolAnterior IS NULL
            THROW 79916,
                ''Usuario no encontrado.'', 1;

        SELECT
            @RolAnterior = Nombre
        FROM dbo.Roles
        WHERE IDRol = @IDRolAnterior;

        SET @IDRolNuevo = @IDRolAnterior;
        SET @ActivoNuevo = @ActivoAnterior;

        -- ==================================
        -- 5. RESOLVER CAMBIO SOLICITADO
        -- ==================================

        IF @Rol IS NOT NULL
        BEGIN
            SELECT
                @IDRolNuevo = IDRol
            FROM dbo.Roles
            WHERE Nombre = @Rol;

            IF @IDRolNuevo IS NULL
                THROW 79918,
                    ''El rol solicitado no existe.'', 1;
        END;

        IF @Activo IS NOT NULL
            SET @ActivoNuevo = @Activo;

        SELECT
            @RolNuevo = Nombre
        FROM dbo.Roles
        WHERE IDRol = @IDRolNuevo;

        -- ==================================
        -- 6. PROTEGER ULTIMO ADMINISTRADOR
        -- ==================================

        IF @IDRolAnterior = @IDRolAdmin
           AND @ActivoAnterior = 1
           AND (
                @IDRolNuevo <> @IDRolAdmin
                OR @ActivoNuevo = 0
           )
        BEGIN

            SELECT
                @TotalAdministradores = COUNT_BIG(*)
            FROM dbo.Usuarios WITH (HOLDLOCK)
            WHERE IDRol = @IDRolAdmin
              AND Activo = 1;

            IF @TotalAdministradores <= 1
                THROW 79917,
                    ''No puede quitar el ultimo Administrador activo.'',
                    1;
        END;

        -- ==================================
        -- 7. APLICAR CAMBIO REAL
        -- ==================================

        IF @IDRolNuevo <> @IDRolAnterior
           OR @ActivoNuevo <> @ActivoAnterior
        BEGIN

            UPDATE dbo.Usuarios
            SET
                IDRol = @IDRolNuevo,
                Activo = @ActivoNuevo
            WHERE IDUsuario = @IDUsuarioObjetivo;

            IF @@ROWCOUNT <> 1
                THROW 79919,
                    ''No se pudo actualizar el usuario.'', 1;

            -- Revocar sesiones renovables.
            -- Los access tokens JWT actuales
            -- se validaran en el middleware
            -- reforzado de la API.

            UPDATE dbo.RefreshTokens
            SET RevocadoEn = SYSUTCDATETIME()
            WHERE IDUsuario = @IDUsuarioObjetivo
              AND RevocadoEn IS NULL;

            -- ==================================
            -- 8. AUDITORIA
            -- ==================================

            SET @IDEntidad = CONVERT(
                VARCHAR(40),
                @IDUsuarioObjetivo
            );

            SET @Accion = CASE
                WHEN @Rol IS NOT NULL
                    THEN ''ACTUALIZAR''
                WHEN @ActivoNuevo = 1
                    THEN ''ACTIVAR''
                ELSE ''DESACTIVAR''
            END;

            SELECT @ValoresAnteriores = (
                SELECT
                    @RolAnterior AS rol,
                    @ActivoAnterior AS activo
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            SELECT @ValoresNuevos = (
                SELECT
                    @RolNuevo AS rol,
                    @ActivoNuevo AS activo
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            EXEC dbo.SP_Auditoria_RegistrarCambio
                @IDUsuario = @IDUsuarioActor,
                @Modulo = ''USUARIOS'',
                @Entidad = ''Usuarios'',
                @IDEntidad = @IDEntidad,
                @Accion = @Accion,
                @ValoresAnteriores = @ValoresAnteriores,
                @ValoresNuevos = @ValoresNuevos;
        END;

        -- Si los datos eran iguales, no se
        -- genera auditoria ni revocacion.

        COMMIT TRANSACTION;

        -- ==================================
        -- 9. DEVOLVER DATOS ACTUALIZADOS
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
        WHERE u.IDUsuario = @IDUsuarioObjetivo;

    END TRY
    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        -- ======================================
        -- 3. PERMISOS DE LA API
        -- ======================================

        IF DATABASE_PRINCIPAL_ID(
            N'shopcart_api'
        ) IS NULL
            THROW 79903,
                'No existe el usuario shopcart_api.', 1;

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Usuarios_ActualizarSeguridadAdministracion
        TO [shopcart_api];

        -- ======================================
        -- 4. REGISTRAR MIGRACION
        -- ======================================

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            55,
            N'055_AdminUsersSecurityChanges'
        );

        PRINT
            'OK: Migracion 055 aplicada correctamente.';

    END
    ELSE
    BEGIN

        IF OBJECT_ID(
            N'dbo.SP_Usuarios_ActualizarSeguridadAdministracion',
            N'P'
        ) IS NULL
            THROW 79904,
                'Migracion registrada sin procedimiento.', 1;

        PRINT 'OK: Migracion 055 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO
