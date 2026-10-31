USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. Validar dependencia
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 25
    )
        THROW 66001,
            'Primero ejecute la migracion 025.', 1;

    -- 2. Comprobar si ya fue aplicada
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 26
    )
    BEGIN
        -- Evitar sobrescribir objetos existentes
        IF OBJECT_ID(N'dbo.Pedidos', N'U') IS NOT NULL
           OR OBJECT_ID(N'dbo.DetallesPedido', N'U') IS NOT NULL
           OR OBJECT_ID(N'dbo.Pagos', N'U') IS NOT NULL
           OR OBJECT_ID(N'dbo.HistorialEstadosPedido', N'U') IS NOT NULL
            THROW 66002,
                'Ya existen tablas del modulo de pedidos.',
                1;

        -- ==========================================
        -- 3. PEDIDOS
        -- ==========================================
        CREATE TABLE dbo.Pedidos (
            IDPedido BIGINT IDENTITY(1,1) NOT NULL,
            IDUsuario INT NOT NULL,
            IDCarrito BIGINT NOT NULL,
            IDReserva BIGINT NOT NULL,
            IDDireccion INT NOT NULL,

            ClaveIdempotencia VARCHAR(100)
                COLLATE Latin1_General_100_BIN2
                NOT NULL,

            HashSolicitud BINARY(32) NOT NULL,

            Estado VARCHAR(20) NOT NULL
                CONSTRAINT DF_Pedidos_Estado
                DEFAULT ('PAGADO'),

            Subtotal DECIMAL(19,2) NOT NULL,
            Descuento DECIMAL(19,2) NOT NULL
                CONSTRAINT DF_Pedidos_Descuento
                DEFAULT (0),
            Total DECIMAL(19,2) NOT NULL,

            CodigoCupon NVARCHAR(50) NULL,

            -- Copia historica de la direccion
            EntregaDestinatario NVARCHAR(150) NOT NULL,
            EntregaTelefono NVARCHAR(25) NOT NULL,
            EntregaDepartamento NVARCHAR(100) NOT NULL,
            EntregaMunicipio NVARCHAR(100) NOT NULL,
            EntregaDireccionLinea1 NVARCHAR(250) NOT NULL,
            EntregaReferencia NVARCHAR(250) NULL,

            FechaCreacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_Pedidos_FechaCreacion
                DEFAULT (SYSUTCDATETIME()),

            FechaActualizacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_Pedidos_FechaActualizacion
                DEFAULT (SYSUTCDATETIME()),

            CONSTRAINT PK_Pedidos
                PRIMARY KEY (IDPedido),

            CONSTRAINT FK_Pedidos_Usuarios
                FOREIGN KEY (IDUsuario)
                REFERENCES dbo.Usuarios(IDUsuario),

            CONSTRAINT FK_Pedidos_Carritos
                FOREIGN KEY (IDCarrito)
                REFERENCES dbo.Carritos(IDCarrito),

            CONSTRAINT FK_Pedidos_Reservas
                FOREIGN KEY (IDReserva)
                REFERENCES dbo.ReservasInventario(IDReserva),

            CONSTRAINT FK_Pedidos_Direcciones
                FOREIGN KEY (IDDireccion)
                REFERENCES dbo.Direcciones(IDDireccion),

            CONSTRAINT UQ_Pedidos_Carrito
                UNIQUE (IDCarrito),

            CONSTRAINT UQ_Pedidos_Reserva
                UNIQUE (IDReserva),

            CONSTRAINT UQ_Pedidos_Idempotencia
                UNIQUE (IDUsuario, ClaveIdempotencia),

            CONSTRAINT CK_Pedidos_Estado
                CHECK (
                    Estado IN (
                        'PAGADO',
                        'PREPARANDO',
                        'DESPACHADO',
                        'ENTREGADO',
                        'CANCELADO',
                        'DEVUELTO_PARCIAL',
                        'DEVUELTO_TOTAL'
                    )
                ),

            CONSTRAINT CK_Pedidos_Totales
                CHECK (
                    Subtotal >= 0
                    AND Descuento >= 0
                    AND Descuento <= Subtotal
                    AND Total = Subtotal - Descuento
                ),

            CONSTRAINT CK_Pedidos_Idempotencia
                CHECK (LEN(ClaveIdempotencia) >= 16)
        );

        -- ==========================================
        -- 4. DETALLES DEL PEDIDO
        -- ==========================================
        CREATE TABLE dbo.DetallesPedido (
            IDDetallePedido BIGINT IDENTITY(1,1) NOT NULL,
            IDPedido BIGINT NOT NULL,
            IDVariante INT NOT NULL,
            IDCategoria INT NOT NULL,

            -- Datos historicos del producto
            SKU NVARCHAR(64) NOT NULL,
            NombreProducto NVARCHAR(200) NOT NULL,
            PrecioUnitario DECIMAL(19,2) NOT NULL,
            Cantidad INT NOT NULL,
            ImporteLinea DECIMAL(19,2) NOT NULL,

            CantidadDevuelta INT NOT NULL
                CONSTRAINT DF_DetallesPedido_Devuelta
                DEFAULT (0),

            CONSTRAINT PK_DetallesPedido
                PRIMARY KEY (IDDetallePedido),

            CONSTRAINT FK_DetallesPedido_Pedidos
                FOREIGN KEY (IDPedido)
                REFERENCES dbo.Pedidos(IDPedido),

            CONSTRAINT FK_DetallesPedido_Variantes
                FOREIGN KEY (IDVariante)
                REFERENCES dbo.Variantes(IDVariante),

            CONSTRAINT FK_DetallesPedido_Categorias
                FOREIGN KEY (IDCategoria)
                REFERENCES dbo.Categorias(IDCategoria),

            CONSTRAINT UQ_DetallesPedido_Variante
                UNIQUE (IDPedido, IDVariante),

            CONSTRAINT CK_DetallesPedido_Cantidades
                CHECK (
                    Cantidad > 0
                    AND CantidadDevuelta >= 0
                    AND CantidadDevuelta <= Cantidad
                ),

            CONSTRAINT CK_DetallesPedido_Importe
                CHECK (
                    PrecioUnitario >= 0
                    AND ImporteLinea = PrecioUnitario * Cantidad
                )
        );

        -- ==========================================
        -- 5. PAGOS
        -- ==========================================
        CREATE TABLE dbo.Pagos (
            IDPago BIGINT IDENTITY(1,1) NOT NULL,
            IDPedido BIGINT NOT NULL,

            MetodoPago VARCHAR(20) NOT NULL
                CONSTRAINT DF_Pagos_Metodo
                DEFAULT ('SIMULADO'),

            Estado VARCHAR(20) NOT NULL,
            Monto DECIMAL(19,2) NOT NULL,

            ReferenciaPago NVARCHAR(100) NULL,

            FechaCreacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_Pagos_FechaCreacion
                DEFAULT (SYSUTCDATETIME()),

            FechaConfirmacion DATETIME2(3) NULL,

            CONSTRAINT PK_Pagos
                PRIMARY KEY (IDPago),

            CONSTRAINT FK_Pagos_Pedidos
                FOREIGN KEY (IDPedido)
                REFERENCES dbo.Pedidos(IDPedido),

            -- Un unico registro de pago por pedido
            CONSTRAINT UQ_Pagos_Pedido
                UNIQUE (IDPedido),

            CONSTRAINT CK_Pagos_Metodo
                CHECK (MetodoPago = 'SIMULADO'),

            CONSTRAINT CK_Pagos_Estado
                CHECK (
                    Estado IN (
                        'PENDIENTE',
                        'APROBADO',
                        'RECHAZADO',
                        'REEMBOLSADO'
                    )
                ),

            CONSTRAINT CK_Pagos_Monto
                CHECK (Monto >= 0)
        );

        -- ==========================================
        -- 6. HISTORIAL DE ESTADOS
        -- ==========================================
        CREATE TABLE dbo.HistorialEstadosPedido (
            IDHistorialPedido BIGINT IDENTITY(1,1) NOT NULL,
            IDPedido BIGINT NOT NULL,
            IDUsuario INT NOT NULL,

            EstadoAnterior VARCHAR(20) NULL,
            EstadoNuevo VARCHAR(20) NOT NULL,
            Observacion NVARCHAR(300) NULL,

            FechaCambio DATETIME2(3) NOT NULL
                CONSTRAINT DF_HistorialPedido_Fecha
                DEFAULT (SYSUTCDATETIME()),

            CONSTRAINT PK_HistorialEstadosPedido
                PRIMARY KEY (IDHistorialPedido),

            CONSTRAINT FK_HistorialPedido_Pedidos
                FOREIGN KEY (IDPedido)
                REFERENCES dbo.Pedidos(IDPedido),

            CONSTRAINT FK_HistorialPedido_Usuarios
                FOREIGN KEY (IDUsuario)
                REFERENCES dbo.Usuarios(IDUsuario)
        );

        -- ==========================================
        -- 7. INDICES DE CONSULTA
        -- ==========================================

        CREATE INDEX IX_Pedidos_Usuario_Fecha
        ON dbo.Pedidos (
            IDUsuario,
            FechaCreacion DESC
        )
        INCLUDE (Estado, Total);

        CREATE INDEX IX_Pedidos_Estado_Fecha
        ON dbo.Pedidos (
            Estado,
            FechaCreacion DESC
        );

        CREATE INDEX IX_DetallesPedido_Variante
        ON dbo.DetallesPedido (
            IDVariante
        )
        INCLUDE (Cantidad, ImporteLinea);

        CREATE INDEX IX_HistorialPedido_Fecha
        ON dbo.HistorialEstadosPedido (
            IDPedido,
            FechaCambio DESC
        );

        -- ==========================================
        -- 8. REGISTRAR MIGRACION
        -- ==========================================
        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            26,
            N'026_OrdersPaymentsTables'
        );

        PRINT 'Migracion 026 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(N'dbo.Pedidos', N'U') IS NULL
           OR OBJECT_ID(N'dbo.DetallesPedido', N'U') IS NULL
           OR OBJECT_ID(N'dbo.Pagos', N'U') IS NULL
           OR OBJECT_ID(N'dbo.HistorialEstadosPedido', N'U') IS NULL
            THROW 66003,
                'Migracion registrada pero faltan tablas.',
                1;

        PRINT 'Migracion 026 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
