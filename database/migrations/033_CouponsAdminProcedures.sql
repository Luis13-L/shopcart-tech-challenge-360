USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Migracion 033: CRUD administrativo de cupones exclusivamente mediante SP.
-- No modifica los SP de checkout ni devoluciones.
BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.SchemaMigrations WHERE Numero = 32)
        THROW 71000, 'Primero ejecute la migracion 032.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 33
    )
    BEGIN
        IF OBJECT_ID(N'dbo.Cupones', N'U') IS NULL
           OR OBJECT_ID(N'dbo.UsosCupon', N'U') IS NULL
            THROW 71002, 'No existen las tablas de cupones.', 1;

        IF OBJECT_ID(N'dbo.SP_Cupones_Crear', N'P') IS NOT NULL
            THROW 71003, 'Ya existe un procedimiento de cupones sin registro de migracion.', 1;

        IF OBJECT_ID(N'dbo.SP_Cupones_Listar', N'P') IS NOT NULL
            THROW 71003, 'Ya existe un procedimiento de cupones sin registro de migracion.', 1;

        IF OBJECT_ID(N'dbo.SP_Cupones_Obtener', N'P') IS NOT NULL
            THROW 71003, 'Ya existe un procedimiento de cupones sin registro de migracion.', 1;

        IF OBJECT_ID(N'dbo.SP_Cupones_Actualizar', N'P') IS NOT NULL
            THROW 71003, 'Ya existe un procedimiento de cupones sin registro de migracion.', 1;

        IF OBJECT_ID(N'dbo.SP_Cupones_CambiarEstado', N'P') IS NOT NULL
            THROW 71003, 'Ya existe un procedimiento de cupones sin registro de migracion.', 1;

        IF OBJECT_ID(N'dbo.SP_Cupones_ListarUsos', N'P') IS NOT NULL
            THROW 71003, 'Ya existe un procedimiento de cupones sin registro de migracion.', 1;

        EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.SP_Cupones_Crear
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
        SELECT 1 FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1 AND r.Nombre = N''Administrador''
    ) THROW 71001, ''Solo un administrador activo puede gestionar cupones.'', 1;

    SET @Codigo = UPPER(LTRIM(RTRIM(@Codigo)));
    IF @Codigo IS NULL OR LEN(@Codigo) < 3
       OR PATINDEX(''%[^A-Z0-9_-]%'', @Codigo COLLATE Latin1_General_100_BIN2) > 0
        THROW 71010, ''Codigo invalido. Use 3-50 letras, numeros, guion o guion bajo.'', 1;

    IF @TipoDescuento IS NULL OR @TipoDescuento NOT IN (''PORCENTAJE'', ''MONTO_FIJO'')
        THROW 71011, ''TipoDescuento invalido.'', 1;

    IF @Valor IS NULL OR @Valor <= 0
       OR (@TipoDescuento = ''PORCENTAJE'' AND @Valor > 100)
       OR @MontoMinimo IS NULL OR @MontoMinimo < 0
       OR @LimiteUsos IS NULL OR @LimiteUsos <= 0
       OR @LimitePorCliente IS NULL OR @LimitePorCliente <= 0
       OR @FechaInicio IS NULL OR @FechaFin IS NULL OR @FechaFin <= @FechaInicio
       OR @Activo IS NULL
        THROW 71012, ''Valores, limites o fechas invalidos.'', 1;

    DECLARE @IDCupon INT;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF EXISTS (
            SELECT 1 FROM dbo.Cupones WITH (UPDLOCK, HOLDLOCK)
            WHERE Codigo = @Codigo
        ) THROW 71013, ''Ya existe un cupon con ese codigo.'', 1;

        INSERT INTO dbo.Cupones (
            Codigo, TipoDescuento, Valor, MontoMinimo,
            LimiteUsos, LimitePorCliente, FechaInicio, FechaFin, Activo
        ) VALUES (
            @Codigo, @TipoDescuento, @Valor, @MontoMinimo,
            @LimiteUsos, @LimitePorCliente, @FechaInicio, @FechaFin, @Activo
        );

        SET @IDCupon = CONVERT(INT, SCOPE_IDENTITY());
        COMMIT TRANSACTION;

        SELECT IDCupon, Codigo, TipoDescuento, Valor, MontoMinimo,
               LimiteUsos, UsosRealizados, LimitePorCliente,
               FechaInicio, FechaFin, Activo
        FROM dbo.Cupones WHERE IDCupon = @IDCupon;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

        GRANT EXECUTE ON OBJECT::dbo.SP_Cupones_Crear TO [shopcart_api];

        EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.SP_Cupones_Listar
    @IDUsuario INT,
    @SoloActivos BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1 AND r.Nombre = N''Administrador''
    ) THROW 71001, ''Solo un administrador activo puede gestionar cupones.'', 1;

    SELECT IDCupon, Codigo, TipoDescuento, Valor, MontoMinimo,
           LimiteUsos, UsosRealizados, LimitePorCliente,
           FechaInicio, FechaFin, Activo, FechaCreacion
    FROM dbo.Cupones
    WHERE @SoloActivos IS NULL OR Activo = @SoloActivos
    ORDER BY IDCupon DESC;
END;';

        GRANT EXECUTE ON OBJECT::dbo.SP_Cupones_Listar TO [shopcart_api];

        EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.SP_Cupones_Obtener
    @IDUsuario INT,
    @IDCupon INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1 AND r.Nombre = N''Administrador''
    ) THROW 71001, ''Solo un administrador activo puede gestionar cupones.'', 1;

    IF @IDCupon IS NULL OR @IDCupon <= 0
        THROW 71015, ''IDCupon invalido.'', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Cupones WHERE IDCupon = @IDCupon)
        THROW 71014, ''Cupon no encontrado.'', 1;

    SELECT IDCupon, Codigo, TipoDescuento, Valor, MontoMinimo,
           LimiteUsos, UsosRealizados, LimitePorCliente,
           FechaInicio, FechaFin, Activo, FechaCreacion
    FROM dbo.Cupones WHERE IDCupon = @IDCupon;
END;';

        GRANT EXECUTE ON OBJECT::dbo.SP_Cupones_Obtener TO [shopcart_api];

        EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.SP_Cupones_Actualizar
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
        SELECT 1 FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1 AND r.Nombre = N''Administrador''
    ) THROW 71001, ''Solo un administrador activo puede gestionar cupones.'', 1;

    IF @IDCupon IS NULL OR @IDCupon <= 0
        THROW 71015, ''IDCupon invalido.'', 1;

    SET @Codigo = UPPER(LTRIM(RTRIM(@Codigo)));
    IF @Codigo IS NULL OR LEN(@Codigo) < 3
       OR PATINDEX(''%[^A-Z0-9_-]%'', @Codigo COLLATE Latin1_General_100_BIN2) > 0
        THROW 71010, ''Codigo invalido. Use 3-50 letras, numeros, guion o guion bajo.'', 1;

    IF @TipoDescuento IS NULL OR @TipoDescuento NOT IN (''PORCENTAJE'', ''MONTO_FIJO'')
        THROW 71011, ''TipoDescuento invalido.'', 1;

    IF @Valor IS NULL OR @Valor <= 0
       OR (@TipoDescuento = ''PORCENTAJE'' AND @Valor > 100)
       OR @MontoMinimo IS NULL OR @MontoMinimo < 0
       OR @LimiteUsos IS NULL OR @LimiteUsos <= 0
       OR @LimitePorCliente IS NULL OR @LimitePorCliente <= 0
       OR @FechaInicio IS NULL OR @FechaFin IS NULL OR @FechaFin <= @FechaInicio
       OR @Activo IS NULL
        THROW 71012, ''Valores, limites o fechas invalidos.'', 1;

    DECLARE @UsosActuales INT, @CodigoAnterior VARCHAR(50),
            @TipoAnterior VARCHAR(15), @ValorAnterior DECIMAL(19,2),
            @MinimoAnterior DECIMAL(19,2), @InicioAnterior DATETIME2(3);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @UsosActuales = UsosRealizados,
               @CodigoAnterior = Codigo, @TipoAnterior = TipoDescuento,
               @ValorAnterior = Valor, @MinimoAnterior = MontoMinimo,
               @InicioAnterior = FechaInicio
        FROM dbo.Cupones WITH (UPDLOCK, HOLDLOCK)
        WHERE IDCupon = @IDCupon;

        IF @UsosActuales IS NULL
            THROW 71014, ''Cupon no encontrado.'', 1;

        IF @LimiteUsos < @UsosActuales
            THROW 71017, ''El limite global no puede ser inferior a los usos realizados.'', 1;

        IF EXISTS (
            SELECT 1 FROM dbo.UsosCupon
            WHERE IDCupon = @IDCupon
            GROUP BY IDUsuario
            HAVING COUNT_BIG(*) > @LimitePorCliente
        ) THROW 71019, ''El limite por cliente es menor a usos existentes.'', 1;

        -- Los descuentos ya utilizados conservan su definicion historica.
        IF @UsosActuales > 0 AND (
            @Codigo <> @CodigoAnterior OR @TipoDescuento <> @TipoAnterior
            OR @Valor <> @ValorAnterior OR @MontoMinimo <> @MinimoAnterior
            OR @FechaInicio <> @InicioAnterior
        ) THROW 71018, ''No se pueden cambiar las condiciones base de un cupon utilizado.'', 1;

        IF EXISTS (
            SELECT 1 FROM dbo.Cupones WITH (UPDLOCK, HOLDLOCK)
            WHERE Codigo = @Codigo AND IDCupon <> @IDCupon
        ) THROW 71013, ''Ya existe un cupon con ese codigo.'', 1;

        UPDATE dbo.Cupones
        SET Codigo = @Codigo,
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
            THROW 71014, ''Cupon no encontrado.'', 1;

        COMMIT TRANSACTION;

        SELECT IDCupon, Codigo, TipoDescuento, Valor, MontoMinimo,
               LimiteUsos, UsosRealizados, LimitePorCliente,
               FechaInicio, FechaFin, Activo
        FROM dbo.Cupones WHERE IDCupon = @IDCupon;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

        GRANT EXECUTE ON OBJECT::dbo.SP_Cupones_Actualizar TO [shopcart_api];

        EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.SP_Cupones_CambiarEstado
    @IDUsuario INT,
    @IDCupon INT,
    @Activo BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1 AND r.Nombre = N''Administrador''
    ) THROW 71001, ''Solo un administrador activo puede gestionar cupones.'', 1;

    IF @IDCupon IS NULL OR @IDCupon <= 0
        THROW 71015, ''IDCupon invalido.'', 1;

    IF @Activo IS NULL
        THROW 71016, ''Estado del cupon invalido.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Cupones WITH (UPDLOCK)
        SET Activo = @Activo
        WHERE IDCupon = @IDCupon;

        IF @@ROWCOUNT <> 1
            THROW 71014, ''Cupon no encontrado.'', 1;

        COMMIT TRANSACTION;

        SELECT IDCupon, Codigo, Activo, UsosRealizados, LimiteUsos
        FROM dbo.Cupones WHERE IDCupon = @IDCupon;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

        GRANT EXECUTE ON OBJECT::dbo.SP_Cupones_CambiarEstado TO [shopcart_api];

        EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.SP_Cupones_ListarUsos
    @IDUsuario INT,
    @IDCupon INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1 AND r.Nombre = N''Administrador''
    ) THROW 71001, ''Solo un administrador activo puede gestionar cupones.'', 1;

    IF @IDCupon IS NULL OR @IDCupon <= 0
        THROW 71015, ''IDCupon invalido.'', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Cupones WHERE IDCupon = @IDCupon)
        THROW 71014, ''Cupon no encontrado.'', 1;

    SELECT IDUsoCupon, IDCupon, IDPedido, IDUsuario,
           MontoDescuento, FechaUso
    FROM dbo.UsosCupon
    WHERE IDCupon = @IDCupon
    ORDER BY IDUsoCupon DESC;
END;';

        GRANT EXECUTE ON OBJECT::dbo.SP_Cupones_ListarUsos TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (Numero, Nombre)
        VALUES (33, N'033_CouponsAdminProcedures');

        PRINT 'OK: Migracion 033 aplicada correctamente.';
    END
    ELSE
    BEGIN
        -- Idempotencia de la migracion; validar que no falten SP.
        IF OBJECT_ID(N'dbo.SP_Cupones_Crear', N'P') IS NULL
            THROW 71004, 'La migracion 033 esta registrada pero falta algun SP.', 1;
        IF OBJECT_ID(N'dbo.SP_Cupones_Listar', N'P') IS NULL
            THROW 71004, 'La migracion 033 esta registrada pero falta algun SP.', 1;
        IF OBJECT_ID(N'dbo.SP_Cupones_Obtener', N'P') IS NULL
            THROW 71004, 'La migracion 033 esta registrada pero falta algun SP.', 1;
        IF OBJECT_ID(N'dbo.SP_Cupones_Actualizar', N'P') IS NULL
            THROW 71004, 'La migracion 033 esta registrada pero falta algun SP.', 1;
        IF OBJECT_ID(N'dbo.SP_Cupones_CambiarEstado', N'P') IS NULL
            THROW 71004, 'La migracion 033 esta registrada pero falta algun SP.', 1;
        IF OBJECT_ID(N'dbo.SP_Cupones_ListarUsos', N'P') IS NULL
            THROW 71004, 'La migracion 033 esta registrada pero falta algun SP.', 1;
        PRINT 'OK: Migracion 033 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
