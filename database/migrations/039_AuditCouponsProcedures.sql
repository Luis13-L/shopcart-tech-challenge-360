USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 38
)
    THROW 73601,
        'Primero ejecute la migracion 038.', 1;

IF OBJECT_ID(
    'dbo.SP_Auditoria_RegistrarCambio', 'P'
) IS NULL
    THROW 73602,
        'Falta el procedimiento de auditoria.', 1;
GO

-- ==========================================
-- 1. AUDITAR CREACION DE CUPONES
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Cupones_Crear
    @IDUsuario INT,
    @Codigo VARCHAR(50),
    @TipoDescuento VARCHAR(15),
    @Valor DECIMAL(19,2),
    @LimiteUsos INT,
    @FechaInicio DATETIME2(3),
    @FechaFin DATETIME2(3),
    @MontoMinimo DECIMAL(19,2) = 0,
    @LimitePorCliente INT = 1,
    @Activo BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1
          AND r.Nombre = 'Administrador'
    )
        THROW 71001, 'Administrador no autorizado.', 1;

    SET @Codigo = UPPER(LTRIM(RTRIM(@Codigo)));

    IF @Codigo IS NULL OR LEN(@Codigo) < 3
       OR PATINDEX(
           '%[^A-Z0-9_-]%',
           @Codigo COLLATE Latin1_General_100_BIN2
       ) > 0
        THROW 71010, 'Codigo de cupon invalido.', 1;

    IF @TipoDescuento IS NULL
       OR @TipoDescuento NOT IN (
           'PORCENTAJE', 'MONTO_FIJO'
       )
        THROW 71011, 'Tipo de descuento invalido.', 1;

    IF @Valor IS NULL OR @Valor <= 0
       OR (@TipoDescuento = 'PORCENTAJE'
           AND @Valor > 100)
       OR @MontoMinimo IS NULL OR @MontoMinimo < 0
       OR @LimiteUsos IS NULL OR @LimiteUsos <= 0
       OR @LimitePorCliente IS NULL
       OR @LimitePorCliente <= 0
       OR @FechaInicio IS NULL
       OR @FechaFin IS NULL
       OR @FechaFin <= @FechaInicio
       OR @Activo IS NULL
        THROW 71012, 'Valores del cupon invalidos.', 1;

    DECLARE @IDCupon INT;
    DECLARE @Despues NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF EXISTS (
            SELECT 1
            FROM dbo.Cupones WITH (UPDLOCK, HOLDLOCK)
            WHERE Codigo = @Codigo
        )
            THROW 71013, 'Cupon duplicado.', 1;

        INSERT INTO dbo.Cupones (
            Codigo, TipoDescuento, Valor,
            MontoMinimo, LimiteUsos,
            LimitePorCliente, FechaInicio,
            FechaFin, Activo
        )
        VALUES (
            @Codigo, @TipoDescuento, @Valor,
            @MontoMinimo, @LimiteUsos,
            @LimitePorCliente, @FechaInicio,
            @FechaFin, @Activo
        );

        SET @IDCupon = CONVERT(
            INT, SCOPE_IDENTITY()
        );

        SELECT @Despues = (
            SELECT
                Codigo AS codigo,
                TipoDescuento AS tipoDescuento,
                Valor AS valor,
                MontoMinimo AS montoMinimo,
                LimiteUsos AS limiteUsos,
                LimitePorCliente AS limitePorCliente,
                FechaInicio AS fechaInicio,
                FechaFin AS fechaFin,
                Activo AS activo
            FROM dbo.Cupones
            WHERE IDCupon = @IDCupon
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.SP_Auditoria_RegistrarCambio
            @IDUsuario = @IDUsuario,
            @Modulo = 'CUPONES',
            @Entidad = 'Cupones',
            @IDEntidad = @IDCupon,
            @Accion = 'CREAR',
            @ValoresAnteriores = NULL,
            @ValoresNuevos = @Despues;

        COMMIT TRANSACTION;

        SELECT
            IDCupon, Codigo, TipoDescuento,
            Valor, MontoMinimo, LimiteUsos,
            UsosRealizados, LimitePorCliente,
            FechaInicio, FechaFin, Activo
        FROM dbo.Cupones
        WHERE IDCupon = @IDCupon;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- ==========================================
-- 2. AUDITAR ACTUALIZACION DE CUPONES
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Cupones_Actualizar
    @IDUsuario INT,
    @IDCupon INT,
    @Codigo VARCHAR(50),
    @TipoDescuento VARCHAR(15),
    @Valor DECIMAL(19,2),
    @LimiteUsos INT,
    @FechaInicio DATETIME2(3),
    @FechaFin DATETIME2(3),
    @MontoMinimo DECIMAL(19,2) = 0,
    @LimitePorCliente INT = 1,
    @Activo BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1
          AND r.Nombre = 'Administrador'
    )
        THROW 71001, 'Administrador no autorizado.', 1;

    IF @IDCupon IS NULL OR @IDCupon <= 0
        THROW 71015, 'IDCupon invalido.', 1;

    SET @Codigo = UPPER(LTRIM(RTRIM(@Codigo)));

    IF @Codigo IS NULL OR LEN(@Codigo) < 3
       OR PATINDEX(
           '%[^A-Z0-9_-]%',
           @Codigo COLLATE Latin1_General_100_BIN2
       ) > 0
        THROW 71010, 'Codigo invalido.', 1;

    IF @TipoDescuento IS NULL
       OR @TipoDescuento NOT IN (
           'PORCENTAJE', 'MONTO_FIJO'
       )
        THROW 71011, 'Tipo invalido.', 1;

    IF @Valor IS NULL OR @Valor <= 0
       OR (@TipoDescuento = 'PORCENTAJE'
           AND @Valor > 100)
       OR @MontoMinimo IS NULL OR @MontoMinimo < 0
       OR @LimiteUsos IS NULL OR @LimiteUsos <= 0
       OR @LimitePorCliente IS NULL
       OR @LimitePorCliente <= 0
       OR @FechaInicio IS NULL
       OR @FechaFin IS NULL
       OR @FechaFin <= @FechaInicio
       OR @Activo IS NULL
        THROW 71012, 'Valores invalidos.', 1;

    DECLARE @UsosActuales INT;
    DECLARE @CodigoAnterior VARCHAR(50);
    DECLARE @TipoAnterior VARCHAR(15);
    DECLARE @ValorAnterior DECIMAL(19,2);
    DECLARE @MinimoAnterior DECIMAL(19,2);
    DECLARE @InicioAnterior DATETIME2(3);

    DECLARE @Antes NVARCHAR(MAX);
    DECLARE @Despues NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @UsosActuales = UsosRealizados,
            @CodigoAnterior = Codigo,
            @TipoAnterior = TipoDescuento,
            @ValorAnterior = Valor,
            @MinimoAnterior = MontoMinimo,
            @InicioAnterior = FechaInicio
        FROM dbo.Cupones WITH (UPDLOCK, HOLDLOCK)
        WHERE IDCupon = @IDCupon;

        IF @UsosActuales IS NULL
            THROW 71014, 'Cupon no encontrado.', 1;

        IF @LimiteUsos < @UsosActuales
            THROW 71017,
                'Limite inferior a los usos realizados.', 1;

        IF EXISTS (
            SELECT 1
            FROM dbo.UsosCupon
            WHERE IDCupon = @IDCupon
            GROUP BY IDUsuario
            HAVING COUNT_BIG(*) > @LimitePorCliente
        )
            THROW 71019,
                'Limite por cliente insuficiente.', 1;

        IF @UsosActuales > 0 AND (
            @Codigo <> @CodigoAnterior
            OR @TipoDescuento <> @TipoAnterior
            OR @Valor <> @ValorAnterior
            OR @MontoMinimo <> @MinimoAnterior
            OR @FechaInicio <> @InicioAnterior
        )
            THROW 71018,
                'No pueden cambiarse las condiciones base de un cupon utilizado.',
                1;

        IF EXISTS (
            SELECT 1
            FROM dbo.Cupones WITH (UPDLOCK, HOLDLOCK)
            WHERE Codigo = @Codigo
              AND IDCupon <> @IDCupon
        )
            THROW 71013, 'Cupon duplicado.', 1;

        SELECT @Antes = (
            SELECT
                Codigo AS codigo,
                TipoDescuento AS tipoDescuento,
                Valor AS valor,
                MontoMinimo AS montoMinimo,
                LimiteUsos AS limiteUsos,
                LimitePorCliente AS limitePorCliente,
                FechaInicio AS fechaInicio,
                FechaFin AS fechaFin,
                Activo AS activo
            FROM dbo.Cupones
            WHERE IDCupon = @IDCupon
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        UPDATE dbo.Cupones
        SET
            Codigo = @Codigo,
            TipoDescuento = @TipoDescuento,
            Valor = @Valor,
            MontoMinimo = @MontoMinimo,
            LimiteUsos = @LimiteUsos,
            LimitePorCliente = @LimitePorCliente,
            FechaInicio = @FechaInicio,
            FechaFin = @FechaFin,
            Activo = @Activo
        WHERE IDCupon = @IDCupon;

        IF @@ROWCOUNT <> 1
            THROW 71014, 'Cupon no encontrado.', 1;

        SELECT @Despues = (
            SELECT
                Codigo AS codigo,
                TipoDescuento AS tipoDescuento,
                Valor AS valor,
                MontoMinimo AS montoMinimo,
                LimiteUsos AS limiteUsos,
                LimitePorCliente AS limitePorCliente,
                FechaInicio AS fechaInicio,
                FechaFin AS fechaFin,
                Activo AS activo
            FROM dbo.Cupones
            WHERE IDCupon = @IDCupon
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.SP_Auditoria_RegistrarCambio
            @IDUsuario = @IDUsuario,
            @Modulo = 'CUPONES',
            @Entidad = 'Cupones',
            @IDEntidad = @IDCupon,
            @Accion = 'ACTUALIZAR',
            @ValoresAnteriores = @Antes,
            @ValoresNuevos = @Despues;

        COMMIT TRANSACTION;

        SELECT
            IDCupon, Codigo, TipoDescuento,
            Valor, MontoMinimo, LimiteUsos,
            UsosRealizados, LimitePorCliente,
            FechaInicio, FechaFin, Activo
        FROM dbo.Cupones
        WHERE IDCupon = @IDCupon;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- ==========================================
-- 3. AUDITAR ACTIVACION / DESACTIVACION
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Cupones_CambiarEstado
    @IDUsuario INT,
    @IDCupon INT,
    @Activo BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1
          AND r.Nombre = 'Administrador'
    )
        THROW 71001, 'Administrador no autorizado.', 1;

    IF @IDCupon IS NULL OR @IDCupon <= 0
        THROW 71015, 'IDCupon invalido.', 1;

    IF @Activo IS NULL
        THROW 71016, 'Estado invalido.', 1;

    DECLARE @ActivoAnterior BIT;
    DECLARE @Antes NVARCHAR(MAX);
    DECLARE @Despues NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @ActivoAnterior = Activo
        FROM dbo.Cupones WITH (UPDLOCK, HOLDLOCK)
        WHERE IDCupon = @IDCupon;

        IF @ActivoAnterior IS NULL
            THROW 71014, 'Cupon no encontrado.', 1;

        UPDATE dbo.Cupones
        SET Activo = @Activo
        WHERE IDCupon = @IDCupon;

        IF @ActivoAnterior <> @Activo
        BEGIN
            SET @Antes = (
                SELECT @ActivoAnterior AS activo
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            SET @Despues = (
                SELECT @Activo AS activo
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            EXEC dbo.SP_Auditoria_RegistrarCambio
                @IDUsuario = @IDUsuario,
                @Modulo = 'CUPONES',
                @Entidad = 'Cupones',
                @IDEntidad = @IDCupon,
                @Accion = CASE
                    WHEN @Activo = 1
                        THEN 'ACTIVAR'
                    ELSE 'DESACTIVAR'
                END,
                @ValoresAnteriores = @Antes,
                @ValoresNuevos = @Despues;
        END;

        COMMIT TRANSACTION;

        SELECT
            IDCupon, Codigo, Activo,
            UsosRealizados, LimiteUsos
        FROM dbo.Cupones
        WHERE IDCupon = @IDCupon;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- ==========================================
-- 4. REGISTRAR MIGRACION
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 39
    )
    BEGIN
        INSERT INTO dbo.SchemaMigrations (
            Numero, Nombre
        )
        VALUES (
            39, N'039_AuditCouponsProcedures'
        );
    END;

    COMMIT TRANSACTION;

    PRINT 'Migracion 039 aplicada correctamente.';

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
