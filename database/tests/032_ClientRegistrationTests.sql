USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Correo NVARCHAR(254) =
    CONCAT(
        N'test-',
        REPLACE(
            CONVERT(NVARCHAR(36), NEWID()),
            N'-', N''
        ),
        N'@shopcart.test'
    );

DECLARE @HashPrueba NVARCHAR(255) =
    N'$2b$12$' + REPLICATE(N'A', 53);

DECLARE @IDUsuario INT;
DECLARE @Rol VARCHAR(30);

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 43
)
    THROW 77101,
        'Primero ejecute la migracion 043.',
        1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ======================================
    -- 1. REGISTRAR CLIENTE
    -- ======================================

    EXEC dbo.SP_Auth_RegistrarCliente
        @Correo = @Correo,
        @PasswordHash = @HashPrueba;

    SELECT
        @IDUsuario = u.IDUsuario,
        @Rol = r.Nombre
    FROM dbo.Usuarios u
    INNER JOIN dbo.Roles r
        ON r.IDRol = u.IDRol
    WHERE u.Correo = @Correo;

    IF @IDUsuario IS NULL
        THROW 77102,
            'No se creo el usuario.', 1;

    IF @Rol <> 'Cliente'
        THROW 77103,
            'El usuario no tiene rol Cliente.',
            1;

    PRINT 'OK: registro con rol Cliente.';

    -- ======================================
    -- 2. VERIFICAR AUDITORIA
    -- ======================================

    IF (
        SELECT COUNT(*)
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'USUARIOS'
          AND Entidad = 'Usuarios'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDUsuario)
          AND Accion = 'CREAR'
          AND IDUsuario = @IDUsuario
    ) <> 1
        THROW 77104,
            'La auditoria no se registro.',
            1;

    IF EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'USUARIOS'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDUsuario)
          AND (
              ValoresNuevos LIKE N'%PasswordHash%'
              OR ValoresNuevos LIKE N'%$2b$%'
          )
    )
        THROW 77105,
            'La auditoria expone el hash.',
            1;

    PRINT 'OK: auditoria sin contrasena.';

    -- ======================================
    -- 3. VERIFICAR CORREO UNICO
    -- ======================================

    IF NOT EXISTS (
        SELECT 1
        FROM sys.key_constraints
        WHERE parent_object_id =
            OBJECT_ID('dbo.Usuarios')
          AND name = 'UQ_Usuarios_Correo'
    )
        THROW 77106,
            'Falta restriccion de correo unico.',
            1;

    PRINT 'OK: restriccion de correo unico.';

    -- ======================================
    -- 4. MOSTRAR RESULTADO
    -- ======================================

    SELECT
        u.IDUsuario,
        u.Correo,
        r.Nombre AS Rol,
        u.Activo
    FROM dbo.Usuarios u
    INNER JOIN dbo.Roles r
        ON r.IDRol = u.IDRol
    WHERE u.IDUsuario = @IDUsuario;

    -- ======================================
    -- 5. REVERTIR CAMBIOS
    -- ======================================

    ROLLBACK TRANSACTION;

    IF EXISTS (
        SELECT 1
        FROM dbo.Usuarios
        WHERE Correo = @Correo
    )
        THROW 77107,
            'El usuario de prueba persiste.',
            1;

    SELECT
        'OK: registro de clientes validado'
            AS Resultado,
        'OK: ROLLBACK completado'
            AS Integridad;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
