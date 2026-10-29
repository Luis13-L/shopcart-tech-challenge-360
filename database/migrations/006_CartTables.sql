
-- ==================================================
-- PROYECTO: ShopCart
-- MIGRACION: 006_CartTables.sql
-- MODULO: Carrito de compras
-- SQL SERVER 2019+
-- ==================================================

USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- Verificar migracion anterior
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 5
    )
    BEGIN
        THROW 54001,
            'Debe ejecutar primero la migracion 005.',
            1;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 6
    )
    BEGIN

        IF OBJECT_ID(N'dbo.Carritos', N'U') IS NOT NULL
           OR OBJECT_ID(N'dbo.DetallesCarrito', N'U') IS NOT NULL
        BEGIN
            THROW 54002,
                'Existen tablas de carrito sin migracion registrada.',
                1;
        END;

        -- ======================================
        -- TABLA: Carritos
        -- ======================================
        CREATE TABLE dbo.Carritos (
            IDCarrito BIGINT IDENTITY(1,1)
                NOT NULL
                CONSTRAINT PK_Carritos PRIMARY KEY,

            IDUsuario INT NULL,

            TokenInvitadoHash BINARY(32) NULL,

            Estado VARCHAR(15) NOT NULL
                CONSTRAINT DF_Carritos_Estado
                DEFAULT ('ACTIVO'),

            FechaCreacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_Carritos_FechaCreacion
                DEFAULT SYSUTCDATETIME(),

            UltimaActividad DATETIME2(3) NOT NULL
                CONSTRAINT DF_Carritos_UltimaActividad
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT FK_Carritos_Usuarios
                FOREIGN KEY (IDUsuario)
                REFERENCES dbo.Usuarios(IDUsuario),

            CONSTRAINT CK_Carritos_Estado
                CHECK (
                    Estado IN (
                        'ACTIVO',
                        'CONVERTIDO',
                        'CANCELADO'
                    )
                ),

            -- Un carrito pertenece a un usuario
            -- autenticado O a un invitado.
            CONSTRAINT CK_Carritos_Propietario
                CHECK (
                    (
                        IDUsuario IS NOT NULL
                        AND TokenInvitadoHash IS NULL
                    )
                    OR
                    (
                        IDUsuario IS NULL
                        AND TokenInvitadoHash IS NOT NULL
                    )
                )
        );

        -- ======================================
        -- TABLA: DetallesCarrito
        -- ======================================
        CREATE TABLE dbo.DetallesCarrito (
            IDDetalleCarrito BIGINT IDENTITY(1,1)
                NOT NULL
                CONSTRAINT PK_DetallesCarrito PRIMARY KEY,

            IDCarrito BIGINT NOT NULL,

            IDVariante INT NOT NULL,

            Cantidad INT NOT NULL,

            FechaActualizacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_DetallesCarrito_Fecha
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT FK_DetallesCarrito_Carritos
                FOREIGN KEY (IDCarrito)
                REFERENCES dbo.Carritos(IDCarrito),

            CONSTRAINT FK_DetallesCarrito_Variantes
                FOREIGN KEY (IDVariante)
                REFERENCES dbo.Variantes(IDVariante),

            CONSTRAINT CK_DetallesCarrito_Cantidad
                CHECK (Cantidad > 0),

            -- No duplicar variantes
            -- dentro del mismo carrito.
            CONSTRAINT UQ_DetallesCarrito_CarritoVariante
                UNIQUE (IDCarrito, IDVariante)
        );

        -- ======================================
        -- INDICES FILTRADOS
        -- ======================================

        -- Un carrito activo por usuario
        CREATE UNIQUE INDEX
            UX_Carritos_UsuarioActivo
        ON dbo.Carritos (IDUsuario)
        WHERE IDUsuario IS NOT NULL
          AND Estado = 'ACTIVO';

        -- Un carrito activo por token invitado
        CREATE UNIQUE INDEX
            UX_Carritos_InvitadoActivo
        ON dbo.Carritos (TokenInvitadoHash)
        WHERE TokenInvitadoHash IS NOT NULL
          AND Estado = 'ACTIVO';

        -- ======================================
        -- REGISTRAR MIGRACION
        -- ======================================
        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            6,
            N'006_CartTables'
        );

        PRINT 'Migracion 006 aplicada correctamente.';

    END
    ELSE
    BEGIN
        PRINT 'La migracion 006 ya fue aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO
