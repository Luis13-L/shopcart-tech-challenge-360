USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ==========================================
-- MIGRACION 043
-- RF-01: REGISTRO PUBLICO DE CLIENTES
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 42
    )
        THROW 77001,
            'Primero ejecute la migracion 042.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 43
    )
    BEGIN

        IF OBJECT_ID(
            N'dbo.SP_Auth_RegistrarCliente', N'P'
        ) IS NOT NULL
            THROW 77002,
                'El procedimiento ya existe sin migracion.',
                1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Auth_RegistrarCliente
    @Correo NVARCHAR(254),
    @PasswordHash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ======================================
    -- 1. NORMALIZAR Y VALIDAR
    -- ======================================

    SET @Correo = LOWER(
        LTRIM(RTRIM(@Correo))
    );

    IF @Correo IS NULL
       OR LEN(@Correo) < 5
       OR LEN(@Correo) > 254
       OR @Correo NOT LIKE N''%_@_%._%''
       OR CHARINDEX(N'' '', @Correo) > 0
        THROW 77010,
            ''Correo electronico invalido.'', 1;

    -- El backend genera este hash con
    -- bcryptjs y un costo minimo de 12.
    -- Nunca recibimos password en texto
    -- plano dentro de SQL Server.

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
        THROW 77011,
            ''Hash de contrasena invalido.'', 1;

    DECLARE @IDRolCliente INT;
    DECLARE @IDUsuario INT;
    DECLARE @IDTexto VARCHAR(40);
    DECLARE @DatosAuditoria NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ==================================
        -- 2. OBTENER ROL CLIENTE
        -- ==================================

        SELECT
            @IDRolCliente = IDRol
        FROM dbo.Roles
        WHERE Nombre = ''Cliente'';

        IF @IDRolCliente IS NULL
            THROW 77012,
                ''No existe el rol Cliente.'', 1;

        -- ==================================
        -- 3. PREVENIR CORREOS DUPLICADOS
        -- ==================================

        IF EXISTS (
            SELECT 1
            FROM dbo.Usuarios
                WITH (UPDLOCK, HOLDLOCK)
            WHERE Correo = @Correo
        )
            THROW 77013,
                ''Correo ya registrado.'', 1;

        -- ==================================
        -- 4. CREAR USUARIO CLIENTE
        -- ==================================

        INSERT INTO dbo.Usuarios (
            IDRol,
            Correo,
            PasswordHash,
            Activo,
            FechaCreacion
        )
        VALUES (
            @IDRolCliente,
            @Correo,
            @PasswordHash,
            1,
            SYSUTCDATETIME()
        );

        SET @IDUsuario =
            CONVERT(INT, SCOPE_IDENTITY());

        -- ==================================
        -- 5. AUDITORIA SIN CONTRASENA
        -- ==================================

        SET @IDTexto =
            CONVERT(VARCHAR(40), @IDUsuario);

        SELECT @DatosAuditoria = (
            SELECT
                @IDUsuario AS idUsuario,
                N''Cliente'' AS rol,
                CAST(1 AS BIT) AS activo
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.SP_Auditoria_RegistrarCambio
            @IDUsuario = @IDUsuario,
            @Modulo = ''USUARIOS'',
            @Entidad = ''Usuarios'',
            @IDEntidad = @IDTexto,
            @Accion = ''CREAR'',
            @ValoresAnteriores = NULL,
            @ValoresNuevos = @DatosAuditoria;

        COMMIT TRANSACTION;

        -- Nunca devolver PasswordHash.
        SELECT
            u.IDUsuario,
            u.Correo,
            r.Nombre AS NombreRol,
            u.FechaCreacion
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r
            ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario;

    END TRY
    BEGIN CATCH
        DECLARE @NumeroError INT =
            ERROR_NUMBER();

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        IF @NumeroError IN (2601, 2627)
            THROW 77013,
                ''Correo ya registrado.'', 1;

        THROW;
    END CATCH;
END;
';

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Auth_RegistrarCliente
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            43,
            N'043_ClientRegistrationProcedure'
        );

        PRINT
            'Migracion 043 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Auth_RegistrarCliente', N'P'
        ) IS NULL
            THROW 77003,
                'Migracion registrada con SP faltante.',
                1;

        PRINT 'Migracion 043 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
