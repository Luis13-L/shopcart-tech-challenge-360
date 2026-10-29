
-- =====================================================
-- PROYECTO: ShopCart
-- MIGRACION: 005_InventoryMovementProcedure.sql
-- OBJETIVO: Registrar movimientos de inventario
-- MOTOR: SQL Server 2019+
-- =====================================================

USE ShopCartDB;
GO

-- Verificar migracion anterior
IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 4
)
BEGIN
    THROW 51000,
        'Primero debe ejecutar la migracion 004.',
        1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.SP_Inventario_RegistrarMovimiento
    @IDVariante INT,
    @IDUsuario INT,
    @TipoMovimiento VARCHAR(20),
    @Cantidad INT,
    @Motivo NVARCHAR(300)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @SaldoAnterior INT;
    DECLARE @SaldoNuevo BIGINT;
    DECLARE @Movimiento BIGINT;
    DECLARE @IDMovimiento BIGINT;
    DECLARE @Fecha DATETIME2(3) = SYSUTCDATETIME();

    -- ==========================================
    -- 1. VALIDACION DE PARAMETROS
    -- ==========================================

    IF @IDVariante IS NULL OR @IDVariante <= 0
        THROW 51001, 'Variante invalida.', 1;

    IF @Cantidad IS NULL OR @Cantidad <= 0
        THROW 51002, 'La cantidad debe ser positiva.', 1;

    IF @Motivo IS NULL
       OR LEN(LTRIM(RTRIM(@Motivo))) = 0
        THROW 51003, 'Debe indicar un motivo.', 1;

    -- Solo movimientos manuales.
    -- Las ventas y devoluciones tendran
    -- procedimientos transaccionales propios.
    IF @TipoMovimiento IS NULL
       OR @TipoMovimiento NOT IN (
           'ENTRADA',
           'AJUSTE_POSITIVO',
           'AJUSTE_NEGATIVO'
       )
    BEGIN
        THROW 51004,
            'Tipo de movimiento no permitido.',
            1;
    END;

    -- Trabajamos con BIGINT para evitar
    -- overflow en los calculos intermedios.
    SET @Movimiento =
        CASE
            WHEN @TipoMovimiento = 'AJUSTE_NEGATIVO'
                THEN -CONVERT(BIGINT, @Cantidad)
            ELSE CONVERT(BIGINT, @Cantidad)
        END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ======================================
        -- 2. VALIDAR AUTORIZACION
        -- ======================================

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios AS u
            INNER JOIN dbo.Roles AS r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuario
              AND u.Activo = 1
              AND r.Nombre IN (
                  'Operador',
                  'Administrador'
              )
        )
        BEGIN
            THROW 51005,
                'Usuario sin permisos de inventario.',
                1;
        END;

        -- ======================================
        -- 3. BLOQUEAR Y LEER EXISTENCIA
        -- ======================================

        SET @SaldoAnterior = NULL;

        SELECT
            @SaldoAnterior = e.CantidadFisica
        FROM dbo.Existencias AS e
            WITH (UPDLOCK, HOLDLOCK)
        WHERE e.IDVariante = @IDVariante;

        IF @SaldoAnterior IS NULL
        BEGIN
            THROW 51006,
                'No existe inventario para la variante.',
                1;
        END;

        -- ======================================
        -- 4. CALCULAR NUEVO SALDO
        -- ======================================

        SET @SaldoNuevo =
            CONVERT(BIGINT, @SaldoAnterior)
            + @Movimiento;

        IF @SaldoNuevo < 0
        BEGIN
            THROW 51007,
                'Existencia insuficiente para el ajuste.',
                1;
        END;

        IF @SaldoNuevo > 2147483647
        BEGIN
            THROW 51008,
                'El saldo supera el limite permitido.',
                1;
        END;

        -- ======================================
        -- 5. ACTUALIZAR EXISTENCIA FISICA
        -- ======================================

        UPDATE dbo.Existencias
        SET
            CantidadFisica = CONVERT(INT, @SaldoNuevo),
            FechaActualizacion = @Fecha
        WHERE IDVariante = @IDVariante;

        -- ======================================
        -- 6. REGISTRAR MOVIMIENTO DEL KARDEX
        -- ======================================

        INSERT INTO dbo.MovimientosInventario (
            IDVariante,
            IDUsuario,
            TipoMovimiento,
            CantidadFirmada,
            SaldoAnterior,
            SaldoPosterior,
            Motivo,
            FechaMovimiento
        )
        VALUES (
            @IDVariante,
            @IDUsuario,
            @TipoMovimiento,
            CONVERT(INT, @Movimiento),
            @SaldoAnterior,
            CONVERT(INT, @SaldoNuevo),
            LTRIM(RTRIM(@Motivo)),
            @Fecha
        );

        SET @IDMovimiento =
            CONVERT(BIGINT, SCOPE_IDENTITY());

        -- ======================================
        -- 7. CONFIRMAR OPERACION
        -- ======================================

        COMMIT TRANSACTION;

        -- Devolver resultado al backend
        SELECT
            @IDMovimiento AS IDMovimientoInventario,
            @IDVariante AS IDVariante,
            @TipoMovimiento AS TipoMovimiento,
            @Movimiento AS CantidadFirmada,
            @SaldoAnterior AS SaldoAnterior,
            @SaldoNuevo AS SaldoPosterior,
            @Fecha AS FechaMovimiento;

    END TRY
    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;

    END CATCH;
END;
GO

-- ==============================================
-- REGISTRAR MIGRACION
-- ==============================================

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 5
)
BEGIN
    INSERT INTO dbo.SchemaMigrations (
        Numero,
        Nombre
    )
    VALUES (
        5,
        N'005_InventoryMovementProcedure'
    );
END;
GO
