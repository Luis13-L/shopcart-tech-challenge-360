USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ==========================================
-- MIGRACION 052
-- COTIZACION DE CUPONES SIN CONSUMO
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 51
    )
        THROW 79600,
            'Primero ejecute la migracion 051.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 52
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Cupones_Cotizar', N'P'
        ) IS NOT NULL
            THROW 79601,
                'El procedimiento ya existe sin migracion.',
                1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Cupones_Cotizar
    @IDUsuario INT,
    @IDCarrito BIGINT,
    @CodigoCupon VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ======================================
    -- 1. VALIDAR PARAMETROS
    -- ======================================

    IF @IDUsuario IS NULL OR @IDUsuario <= 0
        THROW 79610, ''Usuario invalido.'', 1;

    IF @IDCarrito IS NULL OR @IDCarrito <= 0
        THROW 79611, ''Carrito invalido.'', 1;

    SET @CodigoCupon =
        UPPER(LTRIM(RTRIM(@CodigoCupon)));

    IF @CodigoCupon IS NULL
       OR LEN(@CodigoCupon) < 3
       OR @CodigoCupon COLLATE Latin1_General_100_BIN2
          LIKE ''%[^A-Z0-9_-]%''
        THROW 66029, ''Codigo de cupon invalido.'', 1;

    -- ======================================
    -- 2. VARIABLES MONETARIAS
    -- ======================================

    DECLARE @Subtotal DECIMAL(19,2);
    DECLARE @SubtotalElegible DECIMAL(19,2);
    DECLARE @Descuento DECIMAL(19,2) = 0;
    DECLARE @Total DECIMAL(19,2);

    DECLARE @IDCupon INT;
    DECLARE @IDCategoriaCupon INT;
    DECLARE @TipoDescuento VARCHAR(15);
    DECLARE @ValorCupon DECIMAL(19,2);
    DECLARE @MontoMinimo DECIMAL(19,2);
    DECLARE @LimiteUsos INT;
    DECLARE @UsosRealizados INT;
    DECLARE @LimitePorCliente INT;
    DECLARE @UsosCliente BIGINT;

    DECLARE @FechaInicio DATETIME2(3);
    DECLARE @FechaFin DATETIME2(3);
    DECLARE @Activo BIT;
    DECLARE @Ahora DATETIME2(3);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ==================================
        -- 3. VALIDAR CLIENTE ACTIVO
        -- ==================================

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios AS u
            INNER JOIN dbo.Roles AS r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuario
              AND u.Activo = 1
              AND r.Nombre = N''Cliente''
        )
            THROW 79612,
                ''Cliente no autorizado.'', 1;

        -- ==================================
        -- 4. VALIDAR PROPIEDAD DEL CARRITO
        -- ==================================

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Carritos WITH (HOLDLOCK)
            WHERE IDCarrito = @IDCarrito
              AND IDUsuario = @IDUsuario
              AND Estado = ''ACTIVO''
        )
            THROW 79613,
                ''Carrito no disponible.'', 1;

        -- ==================================
        -- 5. OBTENER PRODUCTOS Y PRECIOS
        -- ==================================

        CREATE TABLE #Lineas (
            IDVariante INT NOT NULL PRIMARY KEY,
            IDCategoria INT NOT NULL,
            ImporteLinea DECIMAL(19,2) NOT NULL
        );

        INSERT INTO #Lineas (
            IDVariante,
            IDCategoria,
            ImporteLinea
        )
        SELECT
            d.IDVariante,
            p.IDCategoria,
            CONVERT(
                DECIMAL(19,2),
                v.PrecioActual * d.Cantidad
            )
        FROM dbo.DetallesCarrito AS d WITH (HOLDLOCK)
        INNER JOIN dbo.Variantes AS v WITH (HOLDLOCK)
            ON v.IDVariante = d.IDVariante
        INNER JOIN dbo.Productos AS p WITH (HOLDLOCK)
            ON p.IDProducto = v.IDProducto
        INNER JOIN dbo.Categorias AS ca WITH (HOLDLOCK)
            ON ca.IDCategoria = p.IDCategoria
        WHERE d.IDCarrito = @IDCarrito
          AND d.Cantidad > 0
          AND v.Activa = 1
          AND p.Activo = 1
          AND ca.Activa = 1;

        IF NOT EXISTS (
            SELECT 1 FROM #Lineas
        )
            THROW 79614,
                ''El carrito no tiene productos disponibles.'',
                1;

        -- Evitar cotizar un carrito parcialmente
        -- disponible o con productos desactivados.

        IF (
            SELECT COUNT_BIG(*)
            FROM #Lineas
        ) <> (
            SELECT COUNT_BIG(*)
            FROM dbo.DetallesCarrito WITH (HOLDLOCK)
            WHERE IDCarrito = @IDCarrito
        )
            THROW 79615,
                ''Hay productos no disponibles.'', 1;

        SELECT
            @Subtotal = SUM(ImporteLinea)
        FROM #Lineas;

        -- ==================================
        -- 6. CONSULTAR CUPON
        -- ==================================

        SELECT
            @IDCupon = c.IDCupon,
            @IDCategoriaCupon = c.IDCategoriaAplicable,
            @TipoDescuento = c.TipoDescuento,
            @ValorCupon = c.Valor,
            @MontoMinimo = c.MontoMinimo,
            @LimiteUsos = c.LimiteUsos,
            @UsosRealizados = c.UsosRealizados,
            @LimitePorCliente = c.LimitePorCliente,
            @FechaInicio = c.FechaInicio,
            @FechaFin = c.FechaFin,
            @Activo = c.Activo
        FROM dbo.Cupones AS c WITH (HOLDLOCK)
        WHERE c.Codigo = @CodigoCupon;

        IF @IDCupon IS NULL OR @Activo = 0
            THROW 66030,
                ''Cupon inexistente o inactivo.'', 1;

        -- ==================================
        -- 7. VALIDAR VIGENCIA
        -- ==================================

        SET @Ahora = SYSUTCDATETIME();

        IF @Ahora < @FechaInicio
           OR @Ahora >= @FechaFin
            THROW 66031,
                ''Cupon fuera de vigencia.'', 1;

        -- ==================================
        -- 8. CALCULAR SUBTOTAL ELEGIBLE
        -- ==================================

        IF @IDCategoriaCupon IS NULL
        BEGIN
            SET @SubtotalElegible = @Subtotal;
        END
        ELSE
        BEGIN
            SELECT
                @SubtotalElegible =
                    ISNULL(SUM(ImporteLinea), 0)
            FROM #Lineas
            WHERE IDCategoria = @IDCategoriaCupon;
        END;

        IF @SubtotalElegible <= 0
            THROW 66037,
                ''El cupon no aplica a estos productos.'',
                1;

        IF @SubtotalElegible < @MontoMinimo
            THROW 66032,
                ''Subtotal elegible inferior al minimo.'',
                1;

        -- ==================================
        -- 9. VALIDAR LIMITES DE USO
        -- ==================================

        IF @UsosRealizados >= @LimiteUsos
            THROW 66033,
                ''Cupon sin usos disponibles.'', 1;

        SELECT
            @UsosCliente = COUNT_BIG(*)
        FROM dbo.UsosCupon WITH (HOLDLOCK)
        WHERE IDCupon = @IDCupon
          AND IDUsuario = @IDUsuario;

        IF @UsosCliente >= @LimitePorCliente
            THROW 66034,
                ''Limite por cliente alcanzado.'',
                1;

        -- ==================================
        -- 10. CALCULAR DESCUENTO
        -- ==================================

        IF @TipoDescuento = ''PORCENTAJE''
        BEGIN
            SET @Descuento = CONVERT(
                DECIMAL(19,2),
                ROUND(
                    @SubtotalElegible * @ValorCupon
                    / 100.00,
                    2
                )
            );
        END
        ELSE IF @TipoDescuento = ''MONTO_FIJO''
        BEGIN
            SET @Descuento = @ValorCupon;
        END
        ELSE
        BEGIN
            THROW 66036,
                ''Tipo de cupon no soportado.'', 1;
        END;

        -- El descuento no puede superar
        -- el subtotal de productos elegibles.

        IF @Descuento > @SubtotalElegible
            SET @Descuento = @SubtotalElegible;

        IF @Descuento <= 0
            THROW 66035,
                ''El cupon no genera descuento.'',
                1;

        SET @Total = @Subtotal - @Descuento;

        -- ==================================
        -- 11. DEVOLVER COTIZACION
        -- ==================================

        SELECT
            @IDCarrito AS IDCarrito,
            @CodigoCupon AS CodigoCupon,
            @TipoDescuento AS TipoDescuento,
            @ValorCupon AS Valor,
            @IDCategoriaCupon AS IDCategoriaAplicable,
            @Subtotal AS Subtotal,
            @SubtotalElegible AS SubtotalElegible,
            @Descuento AS Descuento,
            @Total AS Total;

        -- La cotizacion NO inserta registros,
        -- NO incrementa usos y NO genera pedidos.

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        -- Acceso a datos exclusivamente mediante SP.
        GRANT EXECUTE
        ON OBJECT::dbo.SP_Cupones_Cotizar
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            52,
            N'052_CouponQuoteProcedure'
        );

        PRINT
            'OK: Migracion 052 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Cupones_Cotizar', N'P'
        ) IS NULL
            THROW 79602,
                'Migracion registrada sin procedimiento.',
                1;

        PRINT 'OK: Migracion 052 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
