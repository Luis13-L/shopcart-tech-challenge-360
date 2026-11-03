USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- =====================================================
-- TEST 039: CUPONES POR CATEGORIA
-- ShopCart - Tech Challenge 360
--
-- Migracion requerida: 050
--
-- Escenario:
-- Categoria A: 2 unidades x Q10 = Q20
-- Categoria B: 1 unidad  x Q20 = Q20
--
-- Subtotal: Q40
-- Cupon: 10% exclusivo para Categoria A
-- Descuento esperado: Q2
-- Total esperado: Q38
--
-- Devoluciones:
-- Categoria B (sin descuento): Q20
-- Categoria A (con descuento): Q18
-- Total reembolsado: Q38
--
-- Todas las operaciones se revierten.
-- =====================================================

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 50
)
    THROW 79200,
        'Ejecute primero la migracion 050.', 1;
GO

-- ==========================================
-- VARIABLES DEL TEST
-- ==========================================

DECLARE @Marca VARCHAR(40) =
    CONCAT(
        'T050_',
        LEFT(
            REPLACE(
                CONVERT(VARCHAR(36), NEWID()),
                '-',
                ''
            ),
            20
        )
    );

DECLARE @Admin INT;
DECLARE @Cliente INT;
DECLARE @RolCliente INT;

DECLARE @CatA INT;
DECLARE @CatB INT;

DECLARE @Producto INT;
DECLARE @VarianteA INT;
DECLARE @VarianteB INT;

DECLARE @Cupon INT;
DECLARE @Carrito BIGINT;
DECLARE @Direccion INT;

DECLARE @Reserva BIGINT;
DECLARE @Pedido BIGINT;

DECLARE @DetalleA BIGINT;
DECLARE @DetalleB BIGINT;

DECLARE @ClaveCompra VARCHAR(100) =
    CONVERT(VARCHAR(36), NEWID());

DECLARE @ClaveA VARCHAR(100) =
    CONVERT(VARCHAR(36), NEWID());

DECLARE @ClaveB VARCHAR(100) =
    CONVERT(VARCHAR(36), NEWID());

DECLARE @FechaInicio DATETIME2(3) =
    DATEADD(DAY, -1, SYSUTCDATETIME());

DECLARE @FechaFin DATETIME2(3) =
    DATEADD(DAY, 1, SYSUTCDATETIME());

-- ==========================================
-- CAPTURAR RESULTADO DEL CHECKOUT
-- ==========================================

DECLARE @Compra TABLE (
    IDPedido BIGINT,
    IDCarrito BIGINT,
    IDReserva BIGINT,
    Estado VARCHAR(20),
    Subtotal DECIMAL(19,2),
    Descuento DECIMAL(19,2),
    Total DECIMAL(19,2),
    Reutilizado BIT
);

-- ==========================================
-- CAPTURAR DEVOLUCIONES
-- ==========================================

DECLARE @DevA TABLE (
    IDDevolucion BIGINT,
    IDPedido BIGINT,
    IDDetallePedido BIGINT,
    Cantidad INT,
    MontoReembolso DECIMAL(19,2),
    EstadoPedido VARCHAR(20),
    Reutilizado BIT
);

DECLARE @DevB TABLE (
    IDDevolucion BIGINT,
    IDPedido BIGINT,
    IDDetallePedido BIGINT,
    Cantidad INT,
    MontoReembolso DECIMAL(19,2),
    EstadoPedido VARCHAR(20),
    Reutilizado BIT
);

-- ==========================================
-- 1. IDENTIFICAR ADMINISTRADOR
-- ==========================================

SELECT TOP (1)
    @Admin = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Administrador'
  AND u.Activo = 1
ORDER BY u.IDUsuario;

SELECT
    @RolCliente = IDRol
FROM dbo.Roles
WHERE Nombre = 'Cliente';

IF @Admin IS NULL
   OR @RolCliente IS NULL
    THROW 79201,
        'Faltan roles de prueba.', 1;

BEGIN TRY

    BEGIN TRANSACTION;

    -- ==========================================
    -- 2. CREAR CLIENTE TEMPORAL
    -- ==========================================

    INSERT INTO dbo.Usuarios (
        IDRol,
        Correo,
        PasswordHash,
        Activo
    )
    VALUES (
        @RolCliente,
        CONCAT(@Marca, '@shopcart.test'),
        N'HASH_FICTICIO_SOLO_TEST',
        1
    );

    SET @Cliente =
        CONVERT(INT, SCOPE_IDENTITY());

    PRINT 'OK: cliente temporal creado.';

    -- ==========================================
    -- 3. CREAR CATEGORIAS
    -- ==========================================

    INSERT INTO dbo.Categorias (
        Nombre,
        Activa
    )
    VALUES (
        CONCAT(@Marca, '_A'),
        1
    );

    SET @CatA =
        CONVERT(INT, SCOPE_IDENTITY());

    INSERT INTO dbo.Categorias (
        Nombre,
        Activa
    )
    VALUES (
        CONCAT(@Marca, '_B'),
        1
    );

    SET @CatB =
        CONVERT(INT, SCOPE_IDENTITY());

    PRINT 'OK: dos categorias creadas.';

    -- ==========================================
    -- 4. PRODUCTO DE CATEGORIA A
    -- 2 UNIDADES X Q10
    -- ==========================================

    INSERT INTO dbo.Productos (
        IDCategoria,
        Nombre,
        Activo
    )
    VALUES (
        @CatA,
        CONCAT(@Marca, '_ProductoA'),
        1
    );

    SET @Producto =
        CONVERT(INT, SCOPE_IDENTITY());

    INSERT INTO dbo.Variantes (
        IDProducto,
        SKU,
        PrecioActual,
        Activa
    )
    VALUES (
        @Producto,
        CONCAT(@Marca, '_SKU_A'),
        10.00,
        1
    );

    SET @VarianteA =
        CONVERT(INT, SCOPE_IDENTITY());

    -- ==========================================
    -- 5. PRODUCTO DE CATEGORIA B
    -- 1 UNIDAD X Q20
    -- ==========================================

    INSERT INTO dbo.Productos (
        IDCategoria,
        Nombre,
        Activo
    )
    VALUES (
        @CatB,
        CONCAT(@Marca, '_ProductoB'),
        1
    );

    SET @Producto =
        CONVERT(INT, SCOPE_IDENTITY());

    INSERT INTO dbo.Variantes (
        IDProducto,
        SKU,
        PrecioActual,
        Activa
    )
    VALUES (
        @Producto,
        CONCAT(@Marca, '_SKU_B'),
        20.00,
        1
    );

    SET @VarianteB =
        CONVERT(INT, SCOPE_IDENTITY());

    PRINT 'OK: productos y variantes creados.';

    -- ==========================================
    -- 6. INICIALIZAR INVENTARIO
    -- ==========================================

    -- Migracion 045 crea automaticamente
    -- las existencias para nuevas variantes.

    IF (
        SELECT COUNT(*)
        FROM dbo.Existencias
        WHERE IDVariante IN (
            @VarianteA,
            @VarianteB
        )
    ) <> 2
        THROW 79208,
            'No se inicializaron las existencias.', 1;

    -- Ingresar stock mediante el SP oficial.

    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = @VarianteA,
        @IDUsuario = @Admin,
        @TipoMovimiento = 'ENTRADA',
        @Cantidad = 10,
        @Motivo = N'Test categoria A';

    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = @VarianteB,
        @IDUsuario = @Admin,
        @TipoMovimiento = 'ENTRADA',
        @Cantidad = 10,
        @Motivo = N'Test categoria B';

    PRINT 'OK: inventario inicializado.';

    -- ==========================================
    -- 7. CREAR DIRECCION
    -- ==========================================

    INSERT INTO dbo.Direcciones (
        IDUsuario,
        Destinatario,
        Telefono,
        Departamento,
        Municipio,
        DireccionLinea1
    )
    VALUES (
        @Cliente,
        N'Cliente temporal',
        N'55551234',
        N'Solola',
        N'Solola',
        N'Direccion del test 039'
    );

    SET @Direccion =
        CONVERT(INT, SCOPE_IDENTITY());

    -- ==========================================
    -- 8. CREAR CARRITO
    -- ==========================================

    INSERT INTO dbo.Carritos (
        IDUsuario,
        Estado
    )
    VALUES (
        @Cliente,
        'ACTIVO'
    );

    SET @Carrito =
        CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.DetallesCarrito (
        IDCarrito,
        IDVariante,
        Cantidad
    )
    VALUES
        (@Carrito, @VarianteA, 2),
        (@Carrito, @VarianteB, 1);

    PRINT 'OK: carrito creado.';

    
        -- ==========================================
        -- 9. CREAR CUPON TEMPORAL
        -- ==========================================

        EXEC dbo.SP_Cupones_Crear
            @IDUsuario = @Admin,
            @Codigo = @Marca,
            @TipoDescuento = 'PORCENTAJE',
            @Valor = 10,
            @LimiteUsos = 5,
            @FechaInicio = @FechaInicio,
            @FechaFin = @FechaFin,
            @MontoMinimo = 0,
            @LimitePorCliente = 1,
            @Activo = 0;

        SELECT
            @Cupon = IDCupon
        FROM dbo.Cupones
        WHERE Codigo = @Marca;

        IF @Cupon IS NULL
            THROW 79209,
                'No se creo el cupon.', 1;

        PRINT 'OK: cupon temporal creado.';


    -- ==========================================
    -- 10. ASIGNAR CATEGORIA A
    -- ==========================================

    EXEC dbo.SP_Cupones_AsignarCategoria
        @IDUsuario = @Admin,
        @IDCupon = @Cupon,
        @IDCategoria = @CatA;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Cupones
        WHERE IDCupon = @Cupon
          AND IDCategoriaAplicable = @CatA
    )
        THROW 79210,
            'No se asigno correctamente la categoria.', 1;

    PRINT 'OK: cupon asignado a categoria A.';

    -- ==========================================
    -- 11. ACTIVAR CUPON
    -- ==========================================

    EXEC dbo.SP_Cupones_CambiarEstado
        @IDUsuario = @Admin,
        @IDCupon = @Cupon,
        @Activo = 1;

    -- ==========================================
    -- 12. RESERVAR INVENTARIO
    -- ==========================================

    EXEC dbo.SP_Inventario_ReservarExistencia
        @IDCarrito = @Carrito,
        @IDUsuario = @Cliente,
        @IDReserva = @Reserva OUTPUT;

    IF @Reserva IS NULL
        THROW 79211,
            'No se genero la reserva.', 1;

    PRINT 'OK: inventario reservado.';

    -- ==========================================
    -- 13. CHECKOUT CON CUPON
    -- ==========================================

    INSERT INTO @Compra
    EXEC dbo.SP_Pedidos_ConfirmarCheckout
        @IDUsuario = @Cliente,
        @IDReserva = @Reserva,
        @IDDireccion = @Direccion,
        @ClaveIdempotencia = @ClaveCompra,
        @TotalEsperado = 40.00,
        @CodigoCupon = @Marca;

    SELECT
        @Pedido = IDPedido
    FROM @Compra;

    IF @Pedido IS NULL
        THROW 79212,
            'No se genero el pedido.', 1;

    -- Subtotal general: Q40
    -- Subtotal elegible: Q20
    -- Descuento: 10% de Q20 = Q2
    -- Total: Q38

    IF NOT EXISTS (
        SELECT 1
        FROM @Compra
        WHERE Subtotal = 40.00
          AND Descuento = 2.00
          AND Total = 38.00
          AND Reutilizado = 0
    )
        THROW 79202,
            'El cupon desconto productos no elegibles.', 1;

    PRINT 'OK: checkout Q40 - Q2 = Q38.';

    -- ==========================================
    -- 14. VALIDAR CATEGORIA HISTORICA
    -- ==========================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pedidos
        WHERE IDPedido = @Pedido
          AND IDCategoriaCupon = @CatA
    )
        THROW 79203,
            'No se conservo la categoria historica.', 1;

    SELECT
        @DetalleA = IDDetallePedido
    FROM dbo.DetallesPedido
    WHERE IDPedido = @Pedido
      AND IDVariante = @VarianteA;

    SELECT
        @DetalleB = IDDetallePedido
    FROM dbo.DetallesPedido
    WHERE IDPedido = @Pedido
      AND IDVariante = @VarianteB;

    IF @DetalleA IS NULL
       OR @DetalleB IS NULL
        THROW 79213,
            'No se generaron los detalles.', 1;

    -- ==========================================
    -- 15. CAMBIAR ESTADOS DEL PEDIDO
    -- ==========================================

    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @Pedido,
        @IDUsuario = @Admin,
        @EstadoNuevo = 'PREPARANDO';

    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @Pedido,
        @IDUsuario = @Admin,
        @EstadoNuevo = 'DESPACHADO';

    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @Pedido,
        @IDUsuario = @Admin,
        @EstadoNuevo = 'ENTREGADO';

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pedidos
        WHERE IDPedido = @Pedido
          AND Estado = 'ENTREGADO'
    )
        THROW 79214,
            'El pedido no llego a ENTREGADO.', 1;

    PRINT 'OK: pedido entregado.';

    -- ==========================================
    -- 16. DEVOLVER PRODUCTO B
    -- SIN DESCUENTO = Q20
    -- ==========================================

    INSERT INTO @DevB
    EXEC dbo.SP_Pedidos_RegistrarDevolucion
        @IDPedido = @Pedido,
        @IDDetallePedido = @DetalleB,
        @IDUsuario = @Cliente,
        @Cantidad = 1,
        @Motivo = N'Test producto sin descuento',
        @ClaveIdempotencia = @ClaveB;

    IF NOT EXISTS (
        SELECT 1
        FROM @DevB
        WHERE MontoReembolso = 20.00
          AND EstadoPedido = 'DEVUELTO_PARCIAL'
    )
        THROW 79204,
            'El producto no elegible perdio dinero.', 1;

    PRINT 'OK: producto B reembolsado Q20.';

    -- ==========================================
    -- 17. DEVOLVER PRODUCTO A
    -- CON DESCUENTO = Q18
    -- ==========================================

    INSERT INTO @DevA
    EXEC dbo.SP_Pedidos_RegistrarDevolucion
        @IDPedido = @Pedido,
        @IDDetallePedido = @DetalleA,
        @IDUsuario = @Cliente,
        @Cantidad = 2,
        @Motivo = N'Test producto con descuento',
        @ClaveIdempotencia = @ClaveA;

    IF NOT EXISTS (
        SELECT 1
        FROM @DevA
        WHERE MontoReembolso = 18.00
          AND EstadoPedido = 'DEVUELTO_TOTAL'
    )
        THROW 79205,
            'Reembolso de categoria elegible incorrecto.', 1;

    PRINT 'OK: producto A reembolsado Q18.';

    -- ==========================================
    -- 18. VALIDAR REEMBOLSO TOTAL
    -- ==========================================

    IF (
        SELECT SUM(MontoReembolso)
        FROM dbo.Devoluciones
        WHERE IDPedido = @Pedido
    ) <> 38.00
        THROW 79206,
            'Reembolso total distinto al pago.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pedidos
        WHERE IDPedido = @Pedido
          AND Estado = 'DEVUELTO_TOTAL'
    )
        THROW 79215,
            'El pedido no termino en DEVUELTO_TOTAL.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pagos
        WHERE IDPedido = @Pedido
          AND Estado = 'REEMBOLSADO'
          AND Monto = 38.00
    )
        THROW 79216,
            'El pago no fue marcado como reembolsado.', 1;

    PRINT 'OK: reembolso total Q38.';

    -- ==========================================
    -- 19. VERIFICAR INVENTARIO
    -- ==========================================

    IF (
        SELECT COUNT(*)
        FROM dbo.Existencias
        WHERE IDVariante IN (
            @VarianteA,
            @VarianteB
        )
          AND CantidadFisica = 10
    ) <> 2
        THROW 79207,
            'No se recupero el inventario.', 1;

    -- Dos movimientos de devolucion:
    -- A: +2 unidades
    -- B: +1 unidad

    IF (
        SELECT COUNT(*)
        FROM dbo.MovimientosInventario
        WHERE TipoMovimiento = 'DEVOLUCION'
          AND IDVariante IN (
              @VarianteA,
              @VarianteB
          )
    ) <> 2
        THROW 79217,
            'Cantidad incorrecta de movimientos.', 1;

    PRINT 'OK: inventario y kardex correctos.';

    -- ==========================================
    -- 20. RESULTADO FINAL
    -- ==========================================

    SELECT
        @Pedido AS IDPedidoTemporal,
        CAST(
            40.00 AS DECIMAL(19,2)
        ) AS Subtotal,
        CAST(
            2.00 AS DECIMAL(19,2)
        ) AS Descuento,
        CAST(
            38.00 AS DECIMAL(19,2)
        ) AS TotalPagado,
        (
            SELECT MontoReembolso
            FROM @DevB
        ) AS ReembolsoNoElegible,
        (
            SELECT MontoReembolso
            FROM @DevA
        ) AS ReembolsoElegible,
        'OK' AS Resultado;

    -- ==========================================
    -- 21. ROLLBACK
    -- ==========================================

    ROLLBACK TRANSACTION;

    SELECT
        'OK: cupon por categoria y devoluciones'
            AS Resultado,
        'OK: ROLLBACK completado'
            AS Integridad;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO
