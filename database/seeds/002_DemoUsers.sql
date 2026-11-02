-- ShopCart - usuarios de demostracion (solo desarrollo local)
-- Ejecutar en SSMS como administrador DESPUES de las migraciones 001-045
-- y database/seeds/001_InitialData.sql.
-- Sustituir los tres marcadores por hashes bcrypt $2b$12$ generados
-- localmente. Nunca colocar contrasenas en texto plano en este archivo.

USE ShopCartDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Demo TABLE (
    Correo NVARCHAR(254) COLLATE Latin1_General_100_CI_AS PRIMARY KEY,
    Rol VARCHAR(30) NOT NULL,
    PasswordHash NVARCHAR(255) NOT NULL
);

INSERT INTO @Demo (Correo, Rol, PasswordHash)
VALUES
    (N'admin.demo@shopcart.test', 'Administrador', N'REEMPLAZAR_HASH_ADMIN'),
    (N'operador.demo@shopcart.test', 'Operador', N'REEMPLAZAR_HASH_OPERADOR'),
    (N'cliente.demo@shopcart.test', 'Cliente', N'REEMPLAZAR_HASH_CLIENTE');

-- No ejecutar si faltan hashes bcrypt validos.
IF EXISTS (
    SELECT 1
    FROM @Demo
    WHERE LEN(PasswordHash) <> 60
       OR LEFT(PasswordHash, 4) <> N'$2b$'
       OR COALESCE(TRY_CONVERT(INT, SUBSTRING(PasswordHash, 5, 2)), -1) <> 12
       OR SUBSTRING(PasswordHash, 7, 1) <> N'$'
       OR PATINDEX(
            N'%[^A-Za-z0-9./]%',
            SUBSTRING(PasswordHash, 8, 53) COLLATE Latin1_General_100_BIN2
          ) > 0
)
    THROW 78101, 'Reemplace los tres marcadores por hashes bcrypt de costo 12.', 1;

IF OBJECT_ID(N'dbo.SP_Auditoria_RegistrarCambio', N'P') IS NULL
    THROW 78102, 'Falta la migracion de auditoria 036.', 1;

IF EXISTS (
    SELECT 1
    FROM @Demo AS d
    LEFT JOIN dbo.Roles AS r ON r.Nombre = d.Rol
    WHERE r.IDRol IS NULL
)
    THROW 78103, 'Faltan los roles. Ejecute primero 001_InitialData.sql.', 1;

DECLARE @Creados TABLE (
    IDUsuario INT PRIMARY KEY,
    Correo NVARCHAR(254) COLLATE Latin1_General_100_CI_AS NOT NULL
);

BEGIN TRY
    BEGIN TRANSACTION;

    -- Evita cambiar silenciosamente el rol de un usuario preexistente.
    IF EXISTS (
        SELECT 1
        FROM @Demo AS d
        JOIN dbo.Usuarios AS u WITH (UPDLOCK, HOLDLOCK)
          ON u.Correo = d.Correo
        JOIN dbo.Roles AS r ON r.IDRol = u.IDRol
        WHERE r.Nombre <> d.Rol
    )
        THROW 78104, 'Existe una cuenta de prueba con un rol diferente.', 1;

    -- Crea solo cuentas inexistentes; no sobrescribe claves existentes.
    INSERT INTO dbo.Usuarios (IDRol, Correo, PasswordHash, Activo)
    OUTPUT inserted.IDUsuario, inserted.Correo
        INTO @Creados (IDUsuario, Correo)
    SELECT r.IDRol, d.Correo, d.PasswordHash, 1
    FROM @Demo AS d
    JOIN dbo.Roles AS r ON r.Nombre = d.Rol
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios AS u WITH (UPDLOCK, HOLDLOCK)
        WHERE u.Correo = d.Correo
    );

    -- Audita solamente las cuentas realmente creadas.
    DECLARE @IDUsuario INT;
    DECLARE @Correo NVARCHAR(254);
    DECLARE @Rol VARCHAR(30);
    DECLARE @IDTexto VARCHAR(40);
    DECLARE @Datos NVARCHAR(MAX);

    DECLARE demo_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT c.IDUsuario, c.Correo, d.Rol
        FROM @Creados AS c
        JOIN @Demo AS d ON d.Correo = c.Correo;

    OPEN demo_cursor;
    FETCH NEXT FROM demo_cursor INTO @IDUsuario, @Correo, @Rol;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @IDTexto = CONVERT(VARCHAR(40), @IDUsuario);

        SELECT @Datos = (
            SELECT @IDUsuario AS idUsuario,
                   @Rol AS rol,
                   N'SEED_DEMO' AS origen,
                   CAST(1 AS BIT) AS activo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.SP_Auditoria_RegistrarCambio
            @IDUsuario = @IDUsuario,
            @Modulo = 'USUARIOS',
            @Entidad = 'Usuarios',
            @IDEntidad = @IDTexto,
            @Accion = 'CREAR',
            @ValoresAnteriores = NULL,
            @ValoresNuevos = @Datos;

        FETCH NEXT FROM demo_cursor INTO @IDUsuario, @Correo, @Rol;
    END;

    CLOSE demo_cursor;
    DEALLOCATE demo_cursor;

    COMMIT TRANSACTION;

    SELECT u.IDUsuario, u.Correo, r.Nombre AS Rol, u.Activo,
           CASE WHEN c.IDUsuario IS NULL THEN 'YA_EXISTIA'
                ELSE 'CREADO' END AS Resultado
    FROM @Demo AS d
    JOIN dbo.Usuarios AS u ON u.Correo = d.Correo
    JOIN dbo.Roles AS r ON r.IDRol = u.IDRol
    LEFT JOIN @Creados AS c ON c.IDUsuario = u.IDUsuario
    ORDER BY u.IDUsuario;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
