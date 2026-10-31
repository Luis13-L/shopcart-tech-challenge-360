USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- ==========================================
    -- 1. VALIDAR MIGRACION ANTERIOR
    -- ==========================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 22
    )
        THROW 65600,
            'Primero ejecute la migracion 022.', 1;

    -- ==========================================
    -- 2. EVITAR EJECUCION DUPLICADA
    -- ==========================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 23
    )
    BEGIN

        IF OBJECT_ID(
            N'dbo.ReservasInventario', N'U'
        ) IS NOT NULL
        OR OBJECT_ID(
            N'dbo.DetallesReserva', N'U'
        ) IS NOT NULL
            THROW 65601,
                'Ya existen tablas de reservas sin migracion registrada.',
                1;

        -- ==========================================
        -- 3. TABLA PRINCIPAL DE RESERVAS
        -- ==========================================

        CREATE TABLE dbo.ReservasInventario (
            IDReserva BIGINT IDENTITY(1,1) NOT NULL,
            IDCarrito BIGINT NOT NULL,
            IDUsuario INT NOT NULL,

            Estado VARCHAR(12) NOT NULL
                CONSTRAINT DF_Reservas_Estado
                DEFAULT ('ACTIVA'),

            FechaCreacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_Reservas_FechaCreacion
                DEFAULT (SYSUTCDATETIME()),

            ExpiraEn DATETIME2(3) NOT NULL,

            FechaCierre DATETIME2(3) NULL,

            CONSTRAINT PK_ReservasInventario
                PRIMARY KEY (IDReserva),

            CONSTRAINT FK_Reservas_Carritos
                FOREIGN KEY (IDCarrito)
                REFERENCES dbo.Carritos(IDCarrito),

            CONSTRAINT FK_Reservas_Usuarios
                FOREIGN KEY (IDUsuario)
                REFERENCES dbo.Usuarios(IDUsuario),

            CONSTRAINT CK_Reservas_Estado
                CHECK (
                    Estado IN (
                        'ACTIVA',
                        'CONFIRMADA',
                        'CANCELADA',
                        'VENCIDA'
                    )
                ),

            CONSTRAINT CK_Reservas_Vigencia
                CHECK (ExpiraEn > FechaCreacion)
        );

        -- ==========================================
        -- 4. DETALLES DE LA RESERVA
        -- ==========================================

        CREATE TABLE dbo.DetallesReserva (
            IDDetalleReserva BIGINT IDENTITY(1,1)
                NOT NULL,

            IDReserva BIGINT NOT NULL,
            IDVariante INT NOT NULL,
            Cantidad INT NOT NULL,

            CONSTRAINT PK_DetallesReserva
                PRIMARY KEY (IDDetalleReserva),

            CONSTRAINT FK_DetallesReserva_Reserva
                FOREIGN KEY (IDReserva)
                REFERENCES dbo.ReservasInventario(
                    IDReserva
                ),

            CONSTRAINT FK_DetallesReserva_Variante
                FOREIGN KEY (IDVariante)
                REFERENCES dbo.Variantes(
                    IDVariante
                ),

            CONSTRAINT CK_DetallesReserva_Cantidad
                CHECK (Cantidad > 0),

            CONSTRAINT UQ_DetallesReserva_Variante
                UNIQUE (IDReserva, IDVariante)
        );

        -- ==========================================
        -- 5. INDICES
        -- ==========================================

        -- Solo una reserva con estado ACTIVA
        -- por carrito.
        CREATE UNIQUE INDEX
            UX_Reservas_CarritoActivo
        ON dbo.ReservasInventario(IDCarrito)
        WHERE Estado = 'ACTIVA';

        -- Facilita localizar reservas vigentes
        CREATE INDEX
            IX_Reservas_Activas_Vencimiento
        ON dbo.ReservasInventario(
            ExpiraEn,
            IDReserva
        )
        WHERE Estado = 'ACTIVA';

        -- Facilita sumar las unidades reservadas
        -- para una variante.
        CREATE INDEX
            IX_DetallesReserva_Variante
        ON dbo.DetallesReserva(
            IDVariante,
            IDReserva
        )
        INCLUDE (Cantidad);

        -- ==========================================
        -- 6. REGISTRAR MIGRACION
        -- ==========================================

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            23,
            N'023_InventoryReservationTables'
        );

        PRINT 'Migracion 023 aplicada correctamente.';

    END
    ELSE
    BEGIN
        -- Detectar historial inconsistente
        IF OBJECT_ID(
            N'dbo.ReservasInventario', N'U'
        ) IS NULL
        OR OBJECT_ID(
            N'dbo.DetallesReserva', N'U'
        ) IS NULL
            THROW 65602,
                'Migracion registrada pero faltan tablas.',
                1;

        PRINT 'Migracion 023 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
