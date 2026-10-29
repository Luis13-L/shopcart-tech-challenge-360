
-- ==================================================
-- PROYECTO: ShopCart
-- MIGRACION: 004_InventoryTables.sql
-- MODULO: Inventario y Kardex
-- MOTOR: SQL Server 2019+
-- ==================================================

USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- Verificar dependencia
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 3
    )
    BEGIN
        THROW 50004,
            'Debe ejecutar primero la migracion 003.',
            1;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 4
    )
    BEGIN

        -- Evitar adoptar tablas preexistentes
        -- que no pertenecen a esta migracion.
        IF OBJECT_ID(N'dbo.Existencias', N'U') IS NOT NULL
           OR OBJECT_ID(N'dbo.MovimientosInventario', N'U') IS NOT NULL
        BEGIN
            THROW 50005,
                'Existen tablas de inventario sin migracion registrada.',
                1;
        END;

        -- ======================================
        -- TABLA: Existencias
        -- ======================================
        CREATE TABLE dbo.Existencias (
            IDVariante INT NOT NULL
                CONSTRAINT PK_Existencias
                PRIMARY KEY,

            CantidadFisica INT NOT NULL
                CONSTRAINT DF_Existencias_CantidadFisica
                DEFAULT (0),

            FechaActualizacion DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_Existencias_Fecha
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT FK_Existencias_Variantes
                FOREIGN KEY (IDVariante)
                REFERENCES dbo.Variantes(IDVariante),

            CONSTRAINT CK_Existencias_Cantidad
                CHECK (CantidadFisica >= 0)
        );

        -- ======================================
        -- TABLA: MovimientosInventario
        -- ======================================
        CREATE TABLE dbo.MovimientosInventario (
            IDMovimientoInventario BIGINT
                IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_MovimientosInventario
                PRIMARY KEY,

            IDVariante INT NOT NULL,

            IDUsuario INT NOT NULL,

            TipoMovimiento VARCHAR(20) NOT NULL,

            CantidadFirmada INT NOT NULL,

            SaldoAnterior INT NOT NULL,

            SaldoPosterior INT NOT NULL,

            Motivo NVARCHAR(300) NOT NULL,

            FechaMovimiento DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_MovimientosInventario_Fecha
                DEFAULT SYSUTCDATETIME(),

            -- Relaciones
            CONSTRAINT FK_Movimientos_Variantes
                FOREIGN KEY (IDVariante)
                REFERENCES dbo.Variantes(IDVariante),

            CONSTRAINT FK_Movimientos_Usuarios
                FOREIGN KEY (IDUsuario)
                REFERENCES dbo.Usuarios(IDUsuario),

            -- Tipos permitidos y sus signos
            CONSTRAINT CK_Movimientos_TipoCantidad
                CHECK (
                    (
                        TipoMovimiento IN (
                            'ENTRADA',
                            'AJUSTE_POSITIVO',
                            'DEVOLUCION'
                        )
                        AND CantidadFirmada > 0
                    )
                    OR
                    (
                        TipoMovimiento IN (
                            'SALIDA_VENTA',
                            'AJUSTE_NEGATIVO'
                        )
                        AND CantidadFirmada < 0
                    )
                ),

            -- Saldos validos y consistentes
            CONSTRAINT CK_Movimientos_Saldos
                CHECK (
                    SaldoAnterior >= 0
                    AND SaldoPosterior >= 0
                    AND
                    CONVERT(BIGINT, SaldoPosterior) =
                    CONVERT(BIGINT, SaldoAnterior)
                    + CONVERT(BIGINT, CantidadFirmada)
                ),

            -- Motivo obligatorio
            CONSTRAINT CK_Movimientos_Motivo
                CHECK (
                    LEN(LTRIM(RTRIM(Motivo))) > 0
                )
        );

        -- ======================================
        -- INDICE PARA CONSULTAS DEL KARDEX
        -- ======================================
        CREATE INDEX IX_Movimientos_VarianteFecha
            ON dbo.MovimientosInventario (
                IDVariante,
                FechaMovimiento DESC,
                IDMovimientoInventario DESC
            )
            INCLUDE (
                TipoMovimiento,
                CantidadFirmada,
                SaldoAnterior,
                SaldoPosterior
            );

        -- ======================================
        -- INICIALIZAR EXISTENCIAS
        -- ======================================
        -- Cada variante existente inicia con
        -- saldo fisico igual a cero.
        -- Las entradas posteriores requeriran
        -- un movimiento de kardex.
        INSERT INTO dbo.Existencias (
            IDVariante,
            CantidadFisica
        )
        SELECT
            IDVariante,
            0
        FROM dbo.Variantes;

        -- ======================================
        -- REGISTRAR MIGRACION
        -- ======================================
        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            4,
            N'004_InventoryTables'
        );

        PRINT 'Migracion 004 aplicada correctamente.';
    END
    ELSE
    BEGIN
        PRINT 'La migracion 004 ya fue aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO
