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
        WHERE Numero = 24
    )
        THROW 51020,
            'Primero ejecute la migracion 024.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 25
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Inventario_RegistrarMovimiento',
            N'P'
        ) IS NULL
            THROW 51021,
                'No existe el procedimiento de inventario.',
                1;

        EXEC sys.sp_executesql N'
ALTER PROCEDURE dbo.SP_Inventario_RegistrarMovimiento
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
    DECLARE @Reservadas BIGINT = 0;
    DECLARE @Fecha DATETIME2(3);

    -- 1. Validar parametros.
    IF @IDVariante IS NULL OR @IDVariante <= 0
        THROW 51001, ''Variante invalida.'', 1;

    IF @Cantidad IS NULL OR @Cantidad <= 0
        THROW 51002,
            ''La cantidad debe ser positiva.'', 1;

    IF @Motivo IS NULL
       OR LEN(LTRIM(RTRIM(@Motivo))) = 0
        THROW 51003,
            ''Debe indicar un motivo.'', 1;

    IF @TipoMovimiento IS NULL
       OR @TipoMovimiento NOT IN (
            ''ENTRADA'',
            ''AJUSTE_POSITIVO'',
            ''AJUSTE_NEGATIVO''
       )
        THROW 51004,
            ''Tipo de movimiento no permitido.'', 1;

    SET @Movimiento =
        CASE
            WHEN @TipoMovimiento = ''AJUSTE_NEGATIVO''
                THEN -CONVERT(BIGINT, @Cantidad)
            ELSE CONVERT(BIGINT, @Cantidad)
        END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 2. Autorizar operador o administrador.
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios u
            INNER JOIN dbo.Roles r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuario
              AND u.Activo = 1
              AND r.Nombre IN (
                  ''Operador'',
                  ''Administrador''
              )
        )
            THROW 51005,
                ''Usuario sin permisos de inventario.'',
                1;

        -- 3. Bloquear la variante.
        SELECT
            @SaldoAnterior = CantidadFisica
        FROM dbo.Existencias WITH (
            UPDLOCK,
            HOLDLOCK
        )
        WHERE IDVariante = @IDVariante;

        IF @SaldoAnterior IS NULL
            THROW 51006,
                ''No existe inventario para la variante.'',
                1;

        -- 4. Calcular saldo.
        SET @SaldoNuevo =
            CONVERT(BIGINT, @SaldoAnterior)
            + @Movimiento;

        IF @SaldoNuevo < 0
            THROW 51007,
                ''Existencia insuficiente para el ajuste.'',
                1;

        IF @SaldoNuevo > 2147483647
            THROW 51008,
                ''El saldo supera el limite permitido.'',
                1;

        -- 5. NUEVA VALIDACION:
        -- Proteger las unidades reservadas.
        IF @TipoMovimiento = ''AJUSTE_NEGATIVO''
        BEGIN
            SELECT
                @Reservadas = ISNULL(
                    SUM(CONVERT(BIGINT, d.Cantidad)),
                    0
                )
            FROM dbo.DetallesReserva d
            INNER JOIN dbo.ReservasInventario r
                ON r.IDReserva = d.IDReserva
            WHERE d.IDVariante = @IDVariante
              AND r.Estado = ''ACTIVA''
              AND r.ExpiraEn > SYSUTCDATETIME();

            IF @SaldoNuevo < @Reservadas
                THROW 51009,
                    ''El ajuste compromete unidades reservadas.'',
                    1;
        END;

        -- 6. Actualizar existencia fisica.
        SET @Fecha = SYSUTCDATETIME();

        UPDATE dbo.Existencias
        SET
            CantidadFisica = CONVERT(
                INT, @SaldoNuevo
            ),
            FechaActualizacion = @Fecha
        WHERE IDVariante = @IDVariante;

        -- 7. Registrar movimiento en kardex.
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

        COMMIT TRANSACTION;

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
';

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            25,
            N'025_InventoryRespectReservations'
        );

        PRINT 'Migracion 025 aplicada correctamente.';
    END
    ELSE
        PRINT 'Migracion 025 ya aplicada.';

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
