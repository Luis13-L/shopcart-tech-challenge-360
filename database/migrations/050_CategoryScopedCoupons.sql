USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM dbo.SchemaMigrations WHERE Numero = 49
)
    THROW 79100, 'Ejecute primero la migracion 049.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 50
    )
    BEGIN
        -- ==========================================
        -- 1. GUARDAR ALCANCE DEL CUPON
        -- ==========================================

        IF COL_LENGTH('dbo.Cupones', 'IDCategoriaAplicable') IS NOT NULL
           OR COL_LENGTH('dbo.Pedidos', 'IDCategoriaCupon') IS NOT NULL
            THROW 79101, 'Columnas de alcance ya existentes.', 1;

        ALTER TABLE dbo.Cupones
        ADD IDCategoriaAplicable INT NULL;

        ALTER TABLE dbo.Cupones
        ADD CONSTRAINT FK_Cupones_CategoriaAplicable
        FOREIGN KEY (IDCategoriaAplicable)
        REFERENCES dbo.Categorias(IDCategoria);

        -- Fotografia del alcance al confirmar el pedido.
        ALTER TABLE dbo.Pedidos
        ADD IDCategoriaCupon INT NULL;

        ALTER TABLE dbo.Pedidos
        ADD CONSTRAINT FK_Pedidos_CategoriaCupon
        FOREIGN KEY (IDCategoriaCupon)
        REFERENCES dbo.Categorias(IDCategoria);

        -- ==========================================
        -- 2. ADMINISTRAR ALCANCE DEL CUPON
        -- ==========================================

        EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.SP_Cupones_AsignarCategoria
    @IDUsuario INT,
    @IDCupon INT,
    @IDCategoria INT = NULL
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
          AND r.Nombre = ''Administrador''
    )
        THROW 71001, ''Administrador no autorizado.'', 1;

    IF @IDCupon IS NULL OR @IDCupon <= 0
        THROW 71015, ''Cupon invalido.'', 1;

    IF @IDCategoria IS NOT NULL AND @IDCategoria <= 0
        THROW 71020, ''Categoria invalida.'', 1;

    DECLARE @Anterior INT;
    DECLARE @Usos INT;
    DECLARE @Antes NVARCHAR(MAX);
    DECLARE @Despues NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @Anterior = IDCategoriaAplicable,
            @Usos = UsosRealizados
        FROM dbo.Cupones WITH (UPDLOCK, HOLDLOCK)
        WHERE IDCupon = @IDCupon;

        IF @Usos IS NULL
            THROW 71014, ''Cupon no encontrado.'', 1;

        IF @IDCategoria IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
               FROM dbo.Categorias
               WHERE IDCategoria = @IDCategoria
                 AND Activa = 1
           )
            THROW 71021, ''Categoria inexistente o inactiva.'', 1;

        IF EXISTS (
            SELECT 1
            FROM dbo.UsosCupon
            WHERE IDCupon = @IDCupon
        ) OR @Usos > 0
            THROW 71022,
                ''No puede cambiar el alcance de un cupon utilizado.'', 1;

        IF @Anterior <> @IDCategoria
           OR (@Anterior IS NULL AND @IDCategoria IS NOT NULL)
           OR (@Anterior IS NOT NULL AND @IDCategoria IS NULL)
        BEGIN
            SELECT @Antes = (
                SELECT @Anterior AS idCategoriaAplicable
                FOR JSON PATH,
                    WITHOUT_ARRAY_WRAPPER,
                    INCLUDE_NULL_VALUES
            );

            UPDATE dbo.Cupones
            SET IDCategoriaAplicable = @IDCategoria
            WHERE IDCupon = @IDCupon;

            SELECT @Despues = (
                SELECT @IDCategoria AS idCategoriaAplicable
                FOR JSON PATH,
                    WITHOUT_ARRAY_WRAPPER,
                    INCLUDE_NULL_VALUES
            );

            EXEC dbo.SP_Auditoria_RegistrarCambio
                @IDUsuario = @IDUsuario,
                @Modulo = ''CUPONES'',
                @Entidad = ''Cupones'',
                @IDEntidad = @IDCupon,
                @Accion = ''ACTUALIZAR'',
                @ValoresAnteriores = @Antes,
                @ValoresNuevos = @Despues;
        END;

        COMMIT TRANSACTION;

        SELECT
            IDCupon,
            Codigo,
            TipoDescuento,
            Valor,
            MontoMinimo,
            LimiteUsos,
            UsosRealizados,
            LimitePorCliente,
            FechaInicio,
            FechaFin,
            Activo,
            IDCategoriaAplicable
        FROM dbo.Cupones
        WHERE IDCupon = @IDCupon;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END';

        -- ==========================================
        -- 3. ADAPTAR CHECKOUT EXISTENTE
        -- ==========================================

        DECLARE @Checkout NVARCHAR(MAX) =
            OBJECT_DEFINITION(
                OBJECT_ID(N'dbo.SP_Pedidos_ConfirmarCheckout')
            );

        IF @Checkout IS NULL
           OR CHARINDEX(N'DECLARE @IDCupon INT;', @Checkout) = 0
           OR CHARINDEX(N'@IDCupon = c.IDCupon,', @Checkout) = 0
           OR CHARINDEX(N'IF @Subtotal < @MontoMinimo', @Checkout) = 0
           OR CHARINDEX(N'ROUND(@Subtotal * @ValorCupon / 100.00, 2)', @Checkout) = 0
           OR CHARINDEX(N'IF @Descuento > @Subtotal', @Checkout) = 0
           OR CHARINDEX(N'SET @Descuento = @Subtotal;', @Checkout) = 0
           OR CHARINDEX(N'            CodigoCupon,', @Checkout) = 0
           OR CHARINDEX(N'            @CodigoCupon,', @Checkout) = 0
            THROW 79102,
                'Checkout distinto al esperado; no se aplicaron cambios.', 1;

        -- Declarar categoria y subtotal elegible.
        SET @Checkout = REPLACE(
            @Checkout,
            N'DECLARE @IDCupon INT;',
            N'DECLARE @IDCupon INT;
    DECLARE @IDCategoriaCupon INT;
    DECLARE @SubtotalElegible DECIMAL(19,2);'
        );

        -- Obtener la categoria configurada en el cupon.
        SET @Checkout = REPLACE(
            @Checkout,
            N'@IDCupon = c.IDCupon,',
            N'@IDCupon = c.IDCupon,
                @IDCategoriaCupon = c.IDCategoriaAplicable,'
        );

        -- ==========================================
        -- SUBTOTAL ELEGIBLE Y MINIMO DE COMPRA
        -- ==========================================

        SET @Checkout = REPLACE(
            @Checkout,
            N'IF @Subtotal < @MontoMinimo',
            N'IF @IDCategoriaCupon IS NULL
                SET @SubtotalElegible = @Subtotal;
            ELSE
                SELECT @SubtotalElegible = ISNULL(
                    SUM(ImporteLinea), 0
                )
                FROM #Lineas
                WHERE IDCategoria = @IDCategoriaCupon;

            IF @SubtotalElegible <= 0
                THROW 66037,
                    ''El cupon no aplica a estos productos.'', 1;

            IF @SubtotalElegible < @MontoMinimo'
        );

        -- Porcentaje solo sobre el subtotal elegible.
        SET @Checkout = REPLACE(
            @Checkout,
            N'ROUND(@Subtotal * @ValorCupon / 100.00, 2)',
            N'ROUND(@SubtotalElegible * @ValorCupon / 100.00, 2)'
        );

        -- Un descuento nunca supera la base elegible.
        SET @Checkout = REPLACE(
            @Checkout,
            N'IF @Descuento > @Subtotal',
            N'IF @Descuento > @SubtotalElegible'
        );

        SET @Checkout = REPLACE(
            @Checkout,
            N'SET @Descuento = @Subtotal;',
            N'SET @Descuento = @SubtotalElegible;'
        );

        -- ==========================================
        -- CONSERVAR CATEGORIA HISTORICA
        -- ==========================================

        SET @Checkout = REPLACE(
            @Checkout,
            N'            CodigoCupon,',
            N'            CodigoCupon,
            IDCategoriaCupon,'
        );

        SET @Checkout = REPLACE(
            @Checkout,
            N'            @CodigoCupon,',
            N'            @CodigoCupon,
            @IDCategoriaCupon,'
        );

        -- ==========================================
        -- CORRECCION ERROR 2714: CHECKOUT
        -- ==========================================

        -- OBJECT_DEFINITION puede devolver
        -- CREATE PROCEDURE, CREATE OR ALTER PROCEDURE
        -- o ALTER PROCEDURE.
        --
        -- Normalizar el encabezado para actualizar
        -- el SP existente en lugar de recrearlo.

        DECLARE @PosicionSP INT;

        SET @PosicionSP = CHARINDEX(
            N'PROCEDURE',
            UPPER(@Checkout)
        );

        IF @PosicionSP = 0
           OR UPPER(LEFT(LTRIM(@Checkout), 6))
              NOT IN (N'CREATE', N'ALTER ')
            THROW 79105,
                'Encabezado de checkout no reconocido.', 1;

        SET @Checkout =
            N'ALTER PROCEDURE'
            + SUBSTRING(
                @Checkout,
                @PosicionSP + LEN(N'PROCEDURE'),
                LEN(@Checkout)
            );

        EXEC sys.sp_executesql @Checkout;

        -- ==========================================
        -- 4. ADAPTAR DEVOLUCIONES
        -- ==========================================

        DECLARE @Devolucion NVARCHAR(MAX) =
            OBJECT_DEFINITION(
                OBJECT_ID(N'dbo.SP_Pedidos_RegistrarDevolucion')
            );

        DECLARE @Inicio INT = CHARINDEX(
            N'-- 7. Distribucion proporcional del TOTAL PAGADO.',
            @Devolucion
        );

        DECLARE @Fin INT = CHARINDEX(
            N'-- 8. Reembolso incremental de la linea.',
            @Devolucion
        );

        IF @Devolucion IS NULL
           OR @Inicio = 0
           OR @Fin <= @Inicio
            THROW 79103,
                'Devoluciones distintas a migracion 049.', 1;

        -- Reemplazar solamente el calculo
        -- de distribucion del descuento.

        SET @Devolucion = STUFF(
            @Devolucion,
            @Inicio,
            @Fin - @Inicio,
            N'-- 7. Distribuir descuento solo entre lineas elegibles.

        DECLARE @CategoriaCuponPedido INT;
        DECLARE @CategoriaLinea INT;
        DECLARE @DescuentoTotal DECIMAL(19,2);
        DECLARE @BaseElegible DECIMAL(38,2);

        -- Leer la categoria historica del cupon.
        SELECT
            @CategoriaCuponPedido = IDCategoriaCupon,
            @DescuentoTotal = Descuento
        FROM dbo.Pedidos
        WHERE IDPedido = @IDPedido;

        -- Categoria de la linea que se devuelve.
        SELECT
            @CategoriaLinea = IDCategoria
        FROM dbo.DetallesPedido
        WHERE IDPedido = @IDPedido
          AND IDDetallePedido = @IDDetallePedido;

        -- Calcular subtotal de productos elegibles.
        SELECT @BaseElegible = ISNULL(
            SUM(CONVERT(DECIMAL(38,2), ImporteLinea)), 0
        )
        FROM dbo.DetallesPedido
        WHERE IDPedido = @IDPedido
          AND (
              @CategoriaCuponPedido IS NULL
              OR IDCategoria = @CategoriaCuponPedido
          );

        IF @BaseElegible = 0 AND @DescuentoTotal > 0
            THROW 69031,
                ''No existe una base valida para el descuento.'', 1;

        -- Productos no elegibles:
        -- conservar importe bruto.
        IF @CategoriaCuponPedido IS NOT NULL
           AND @CategoriaLinea <> @CategoriaCuponPedido
            SET @NetoLinea = @ImporteLinea;
        ELSE
        BEGIN
            SELECT @AcumuladoAnterior = ISNULL(
                SUM(CONVERT(DECIMAL(38,2), ImporteLinea)), 0
            )
            FROM dbo.DetallesPedido
            WHERE IDPedido = @IDPedido
              AND IDDetallePedido < @IDDetallePedido
              AND (
                  @CategoriaCuponPedido IS NULL
                  OR IDCategoria = @CategoriaCuponPedido
              );

            SET @AcumuladoActual =
                @AcumuladoAnterior + @ImporteLinea;

            IF @BaseElegible = 0
                SET @NetoLinea = @ImporteLinea;
            ELSE
                SET @NetoLinea = CONVERT(
                    DECIMAL(19,2),
                    @ImporteLinea
                    - (
                        ROUND(
                            @AcumuladoActual * @DescuentoTotal
                            / @BaseElegible, 2
                        )
                        -
                        ROUND(
                            @AcumuladoAnterior * @DescuentoTotal
                            / @BaseElegible, 2
                        )
                    )
                );
        END;

        '
        );

        
        -- ==========================================
        -- CORRECCION DEFINITIVA: DEVOLUCIONES
        -- ==========================================

        -- Buscar la declaración del procedimiento
        -- sin depender de espacios o saltos de línea.
        SET @PosicionSP = CHARINDEX(
            N'PROCEDURE',
            UPPER(@Devolucion)
        );

        IF @Devolucion IS NULL OR @PosicionSP = 0
            THROW 79106,
                'No se encontro la declaracion del procedimiento.',
                1;

        -- Validar que estamos modificando el SP correcto.
        IF CHARINDEX(
            N'SP_PEDIDOS_REGISTRARDEVOLUCION',
            UPPER(
                SUBSTRING(
                    @Devolucion,
                    @PosicionSP + LEN(N'PROCEDURE'),
                    200
                )
            )
        ) = 0
            THROW 79106,
                'El procedimiento recuperado no corresponde a devoluciones.',
                1;

        -- Conservar parametros y cuerpo.
        -- Sustituir solamente la cabecera.
        SET @Devolucion =
            N'ALTER PROCEDURE' +
            SUBSTRING(
                @Devolucion,
                @PosicionSP + LEN(N'PROCEDURE'),
                LEN(@Devolucion)
            );

        -- Actualizar el procedimiento existente.
        EXEC sys.sp_executesql @Devolucion;


        -- ==========================================
        -- 5. CONSULTAS ADMINISTRATIVAS DE CUPONES
        -- ==========================================

        DECLARE @Listar NVARCHAR(MAX) =
            OBJECT_DEFINITION(
                OBJECT_ID(N'dbo.SP_Cupones_Listar')
            );

        DECLARE @Obtener NVARCHAR(MAX) =
            OBJECT_DEFINITION(
                OBJECT_ID(N'dbo.SP_Cupones_Obtener')
            );

        IF @Listar IS NULL OR @Obtener IS NULL
           OR CHARINDEX(
               N'FechaFin, Activo, FechaCreacion',
               @Listar
           ) = 0
           OR CHARINDEX(
               N'FechaFin, Activo, FechaCreacion',
               @Obtener
           ) = 0
            THROW 79104,
                'No se pudieron actualizar las lecturas de cupones.', 1;

        SET @Listar = REPLACE(
            @Listar,
            N'FechaFin, Activo, FechaCreacion',
            N'FechaFin, Activo, IDCategoriaAplicable, FechaCreacion'
        );

        SET @Obtener = REPLACE(
            @Obtener,
            N'FechaFin, Activo, FechaCreacion',
            N'FechaFin, Activo, IDCategoriaAplicable, FechaCreacion'
        );

        -- ==========================================
        -- CORRECCION ERROR 2714: LISTAR CUPONES
        -- ==========================================

        SET @PosicionSP = CHARINDEX(
            N'PROCEDURE',
            UPPER(@Listar)
        );

        IF @PosicionSP = 0
           OR UPPER(LEFT(LTRIM(@Listar), 6))
              NOT IN (N'CREATE', N'ALTER ')
            THROW 79107,
                'Encabezado de listado de cupones no reconocido.', 1;

        SET @Listar =
            N'ALTER PROCEDURE'
            + SUBSTRING(
                @Listar,
                @PosicionSP + LEN(N'PROCEDURE'),
                LEN(@Listar)
            );

        -- ==========================================
        -- CORRECCION ERROR 2714: OBTENER CUPON
        -- ==========================================

        SET @PosicionSP = CHARINDEX(
            N'PROCEDURE',
            UPPER(@Obtener)
        );

        IF @PosicionSP = 0
           OR UPPER(LEFT(LTRIM(@Obtener), 6))
              NOT IN (N'CREATE', N'ALTER ')
            THROW 79108,
                'Encabezado de consulta de cupon no reconocido.', 1;

        SET @Obtener =
            N'ALTER PROCEDURE'
            + SUBSTRING(
                @Obtener,
                @PosicionSP + LEN(N'PROCEDURE'),
                LEN(@Obtener)
            );

        EXEC sys.sp_executesql @Listar;
        EXEC sys.sp_executesql @Obtener;

        -- ==========================================
        -- 6. CONCEDER PERMISOS
        -- ==========================================

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Cupones_AsignarCategoria
        TO [shopcart_api];

        -- ==========================================
        -- 7. REGISTRAR MIGRACION
        -- ==========================================

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            50,
            N'050_CategoryScopedCoupons'
        );

        PRINT 'Migracion 050 aplicada correctamente.';
    END
    ELSE
    BEGIN
        PRINT 'Migracion 050 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
