
-- ==================================================
-- PROYECTO: ShopCart
-- MIGRACION: 002_SecurityTables.sql
-- MODULO: Seguridad y autenticacion
-- MOTOR: SQL Server 2019+
-- ==================================================

USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- Historial de migraciones aplicadas
    IF OBJECT_ID(N'dbo.SchemaMigrations', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.SchemaMigrations (
            Numero INT NOT NULL
                CONSTRAINT PK_SchemaMigrations PRIMARY KEY,

            Nombre NVARCHAR(150) NOT NULL,

            FechaAplicacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_SchemaMigrations_Fecha
                DEFAULT SYSUTCDATETIME()
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 2
    )
    BEGIN

        -- ==========================================
        -- TABLA: Roles
        -- ==========================================
        CREATE TABLE dbo.Roles (
            IDRol INT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_Roles PRIMARY KEY,

            Nombre VARCHAR(30) NOT NULL,

            CONSTRAINT UQ_Roles_Nombre
                UNIQUE (Nombre),

            CONSTRAINT CK_Roles_Nombre
                CHECK (Nombre IN (
                    'Cliente',
                    'Operador',
                    'Administrador'
                ))
        );

        -- ==========================================
        -- TABLA: Usuarios
        -- ==========================================
        CREATE TABLE dbo.Usuarios (
            IDUsuario INT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_Usuarios PRIMARY KEY,

            IDRol INT NOT NULL,

            Correo NVARCHAR(254)
                COLLATE Latin1_General_100_CI_AS NOT NULL,

            PasswordHash NVARCHAR(255) NOT NULL,

            Activo BIT NOT NULL
                CONSTRAINT DF_Usuarios_Activo
                DEFAULT (1),

            FechaCreacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_Usuarios_FechaCreacion
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT FK_Usuarios_Roles
                FOREIGN KEY (IDRol)
                REFERENCES dbo.Roles(IDRol),

            CONSTRAINT UQ_Usuarios_Correo
                UNIQUE (Correo),

            CONSTRAINT CK_Usuarios_Correo
                CHECK (LEN(LTRIM(RTRIM(Correo))) > 3),

            CONSTRAINT CK_Usuarios_PasswordHash
                CHECK (LEN(PasswordHash) > 0)
        );

        -- ==========================================
        -- TABLA: RefreshTokens
        -- ==========================================
        CREATE TABLE dbo.RefreshTokens (
            IDRefreshToken BIGINT IDENTITY(1,1)
                NOT NULL
                CONSTRAINT PK_RefreshTokens PRIMARY KEY,

            IDUsuario INT NOT NULL,

            TokenHash BINARY(32) NOT NULL,

            IDFamilia UNIQUEIDENTIFIER NOT NULL,

            FechaCreacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_RefreshTokens_FechaCreacion
                DEFAULT SYSUTCDATETIME(),

            ExpiraEn DATETIME2(3) NOT NULL,

            RevocadoEn DATETIME2(3) NULL,

            CONSTRAINT FK_RefreshTokens_Usuarios
                FOREIGN KEY (IDUsuario)
                REFERENCES dbo.Usuarios(IDUsuario),

            CONSTRAINT UQ_RefreshTokens_TokenHash
                UNIQUE (TokenHash),

            CONSTRAINT CK_RefreshTokens_Fechas
                CHECK (ExpiraEn > FechaCreacion)
        );

        -- ==========================================
        -- TABLA: Direcciones
        -- ==========================================
        CREATE TABLE dbo.Direcciones (
            IDDireccion INT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_Direcciones PRIMARY KEY,

            IDUsuario INT NOT NULL,

            Destinatario NVARCHAR(150) NOT NULL,

            Telefono NVARCHAR(25) NOT NULL,

            Departamento NVARCHAR(100) NOT NULL,

            Municipio NVARCHAR(100) NOT NULL,

            DireccionLinea1 NVARCHAR(250) NOT NULL,

            Referencia NVARCHAR(250) NULL,

            Activa BIT NOT NULL
                CONSTRAINT DF_Direcciones_Activa
                DEFAULT (1),

            FechaCreacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_Direcciones_FechaCreacion
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT FK_Direcciones_Usuarios
                FOREIGN KEY (IDUsuario)
                REFERENCES dbo.Usuarios(IDUsuario)
        );

        -- ==========================================
        -- INDICES DE ACCESO
        -- ==========================================
        CREATE INDEX IX_Usuarios_IDRol_Activo
            ON dbo.Usuarios(IDRol, Activo);

        CREATE INDEX IX_RefreshTokens_UsuarioFamilia
            ON dbo.RefreshTokens(IDUsuario, IDFamilia);

        CREATE INDEX IX_Direcciones_UsuarioActivo
            ON dbo.Direcciones(IDUsuario, Activa);

        -- Registrar migracion exitosa
        INSERT INTO dbo.SchemaMigrations
            (Numero, Nombre)
        VALUES
            (2, N'002_SecurityTables');

        PRINT 'Migracion 002 aplicada correctamente.';
    END
    ELSE
    BEGIN
        PRINT 'La migracion 002 ya fue aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
