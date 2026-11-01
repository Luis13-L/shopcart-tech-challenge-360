USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 30
    )
        THROW 70001,
            'Primero ejecute la migracion 030.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 31
    )
    BEGIN
        IF OBJECT_ID(N'dbo.Cupones', N'U') IS NOT NULL
           OR OBJECT_ID(N'dbo.UsosCupon', N'U') IS NOT NULL
            THROW 70002,
                'Existen tablas de cupones sin migracion registrada.',
                1;

        -- =========================================
        -- CATALOGO DE CUPONES
        -- =========================================

        CREATE TABLE dbo.Cupones (
            IDCupon INT IDENTITY(1,1) NOT NULL,
            Codigo VARCHAR(50)
                COLLATE Latin1_General_100_CI_AS
                NOT NULL,

            TipoDescuento VARCHAR(15) NOT NULL,
            Valor DECIMAL(19,2) NOT NULL,

            MontoMinimo DECIMAL(19,2) NOT NULL
                CONSTRAINT DF_Cupones_MontoMinimo
                DEFAULT (0),

            LimiteUsos INT NOT NULL,
            UsosRealizados INT NOT NULL
                CONSTRAINT DF_Cupones_UsosRealizados
                DEFAULT (0),

            LimitePorCliente INT NOT NULL
                CONSTRAINT DF_Cupones_LimiteCliente
                DEFAULT (1),

            FechaInicio DATETIME2(3) NOT NULL,
            FechaFin DATETIME2(3) NOT NULL,

            Activo BIT NOT NULL
                CONSTRAINT DF_Cupones_Activo
                DEFAULT (1),

            FechaCreacion DATETIME2(3) NOT NULL
                CONSTRAINT DF_Cupones_FechaCreacion
                DEFAULT (SYSUTCDATETIME()),

            CONSTRAINT PK_Cupones
                PRIMARY KEY (IDCupon),

            CONSTRAINT UQ_Cupones_Codigo
                UNIQUE (Codigo),

            CONSTRAINT CK_Cupones_Tipo
                CHECK (
                    TipoDescuento IN (
                        'PORCENTAJE',
                        'MONTO_FIJO'
                    )
                ),

            CONSTRAINT CK_Cupones_Valor
                CHECK (
                    Valor > 0
                    AND (
                        TipoDescuento <> 'PORCENTAJE'
                        OR Valor <= 100
                    )
                ),

            CONSTRAINT CK_Cupones_MontoMinimo
                CHECK (MontoMinimo >= 0),

            CONSTRAINT CK_Cupones_Limites
                CHECK (
                    LimiteUsos > 0
                    AND UsosRealizados >= 0
                    AND UsosRealizados <= LimiteUsos
                    AND LimitePorCliente > 0
                ),

            CONSTRAINT CK_Cupones_Vigencia
                CHECK (FechaFin > FechaInicio),

            CONSTRAINT CK_Cupones_Codigo
                CHECK (
                    LEN(LTRIM(RTRIM(Codigo))) >= 3
                )
        );

        -- =========================================
        -- HISTORIAL DE USOS DE CUPONES
        -- =========================================

        CREATE TABLE dbo.UsosCupon (
            IDUsoCupon BIGINT IDENTITY(1,1) NOT NULL,
            IDCupon INT NOT NULL,
            IDPedido BIGINT NOT NULL,
            IDUsuario INT NOT NULL,

            MontoDescuento DECIMAL(19,2) NOT NULL,

            FechaUso DATETIME2(3) NOT NULL
                CONSTRAINT DF_UsosCupon_Fecha
                DEFAULT (SYSUTCDATETIME()),

            CONSTRAINT PK_UsosCupon
                PRIMARY KEY (IDUsoCupon),

            CONSTRAINT FK_UsosCupon_Cupon
                FOREIGN KEY (IDCupon)
                REFERENCES dbo.Cupones(IDCupon),

            CONSTRAINT FK_UsosCupon_Pedido
                FOREIGN KEY (IDPedido)
                REFERENCES dbo.Pedidos(IDPedido),

            CONSTRAINT FK_UsosCupon_Usuario
                FOREIGN KEY (IDUsuario)
                REFERENCES dbo.Usuarios(IDUsuario),

            CONSTRAINT UQ_UsosCupon_Pedido
                UNIQUE (IDPedido),

            CONSTRAINT CK_UsosCupon_Descuento
                CHECK (MontoDescuento > 0)
        );

        CREATE INDEX IX_UsosCupon_Cupon_Usuario
        ON dbo.UsosCupon (
            IDCupon,
            IDUsuario
        );

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            31,
            N'031_CouponsTables'
        );

        PRINT 'Migracion 031 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(N'dbo.Cupones', N'U') IS NULL
           OR OBJECT_ID(N'dbo.UsosCupon', N'U') IS NULL
            THROW 70003,
                'Migracion registrada pero faltan tablas.',
                1;

        PRINT 'Migracion 031 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
