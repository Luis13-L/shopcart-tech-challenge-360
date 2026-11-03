USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- =====================================================
-- TEST 038: DEVOLUCIONES CON DESCUENTO
-- Depende de la migracion 049.
-- Todos los cambios se revierten con ROLLBACK.
-- =====================================================

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 49
)
    THROW 79001,
        'Ejecute primero la migracion 049.', 1;
GO

DECLARE @Etiqueta NVARCHAR(80) =
    CONCAT(
        N'TEST049_',
        REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N'')
    );

DECLARE @Correo NVARCHAR(254) =
    CONCAT(@Etiqueta, N'@shopcart.test');

DECLARE @CodigoCupon VARCHAR(50) =
    CONCAT(
        'T049_',
        LEFT(
            REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''),
            16
        )
    );

DECLARE @IDAdmin INT;
DECLARE @IDRolCliente INT;
DECLARE @IDCliente INT;
DECLARE @IDCategoria INT;
DECLARE @IDProducto INT;
DECLARE @VarianteA INT;
DECLARE @VarianteB INT;
DECLARE @IDCarrito BIGINT;
DECLARE @IDDireccion INT;
DECLARE @IDReserva BIGINT;
DECLARE @IDPedido BIGINT;
DECLARE @DetalleA BIGINT;
DECLARE @DetalleB BIGINT;

DECLARE @ClaveCheckout VARCHAR(100) =
    CONVERT(VARCHAR(36), NEWID());

DECLARE @Clave1 VARCHAR(100) =
    CONVERT(VARCHAR(36), NEWID());

DECLARE @Clave2 VARCHAR(100) =
    CONVERT(VARCHAR(36), NEWID());

DECLARE @Clave3 VARCHAR(100) =
    CONVERT(VARCHAR(36), NEWID());

DECLARE @Monto1 DECIMAL(19,2);
DECLARE @Monto2 DECIMAL(19,2);
DECLARE @Monto3 DECIMAL(19,2);
DECLARE @TotalReembolsado DECIMAL(19,2);
DECLARE @CantidadDevoluciones INT;

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

DECLARE @Devolucion1 TABLE (
    IDDevolucion BIGINT,
    IDPedido BIGINT,
    IDDetallePedido BIGINT,
    Cantidad INT,
    MontoReembolso DECIMAL(19,2),
    EstadoPedido VARCHAR(20),
    Reutilizado BIT
);

DECLARE @Reintento TABLE (
    IDDevolucion BIGINT,
    IDPedido BIGINT,
    IDDetallePedido BIGINT,
    Cantidad INT,
    MontoReembolso DECIMAL(19,2),
    EstadoPedido VARCHAR(20),
    Reutilizado BIT
);

DECLARE @Devolucion2 TABLE (
    IDDevolucion BIGINT,
    IDPedido BIGINT,
    IDDetallePedido BIGINT,
    Cantidad INT,
    MontoReembolso DECIMAL(19,2),
    EstadoPedido VARCHAR(20),
    Reutilizado BIT
);

DECLARE @Devolucion3 TABLE (
    IDDevolucion BIGINT,
    IDPedido BIGINT,
    IDDetallePedido BIGINT,
    Cantidad INT,
    MontoReembolso DECIMAL(19,2),
    EstadoPedido VARCHAR(20),
    Reutilizado BIT
);

-- ==========================================
-- PRECONDICIONES
-- ==========================================

SELECT TOP (1)
    @IDAdmin = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Administrador'
  AND u.Activo = 1
ORDER BY u.IDUsuario;

SELECT @IDRolCliente = IDRol
FROM dbo.Roles
WHERE Nombre = 'Cliente';

IF @IDAdmin IS NULL OR @IDRolCliente IS NULL
    THROW 79002,
        'Falta un administrador o el rol Cliente.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ==========================================
    -- 1. CREAR CLIENTE TEMPORAL
    -- ==========================================

    INSERT INTO dbo.Usuarios (
        IDRol,
        Correo,
        PasswordHash,
        Activo
    )
    VALUES (
        @IDRolCliente,
        @Correo,
        N'HASH_FICTICIO_SOLO_PARA_TEST_SQL',
        1
    );

    SET @IDCliente = CONVERT(INT, SCOPE_IDENTITY());

    -- ==========================================
    -- 2. CREAR CATALOGO TEMPORAL
    -- ==========================================

    INSERT INTO dbo.Categorias (
        Nombre, Descripcion, Activa
    )
    VALUES (
        @Etiqueta,
        N'Categoria temporal para test 038',
        1
    );

    SET @IDCategoria = CONVERT(INT, SCOPE_IDENTITY());

    INSERT INTO dbo.Productos (
        IDCategoria,
        Nombre,
        Descripcion,
        Activo
    )
    VALUES (
        @IDCategoria,
        @Etiqueta,
        N'Producto de prueba con dos variantes',
        1
    );

    SET @IDProducto = CONVERT(INT, SCOPE_IDENTITY());

    INSERT INTO dbo.Variantes (
        IDProducto, SKU, PrecioActual, Activa
    )
    VALUES (
        @IDProducto,
        CONCAT(@Etiqueta, N'_A'),
        10.00,
        1
    );

    SET @VarianteA = CONVERT(INT, SCOPE_IDENTITY());

    INSERT INTO dbo.Variantes (
        IDProducto, SKU, PrecioActual, Activa
    )
    VALUES (
        @IDProducto,
        CONCAT(@Etiqueta, N'_B'),
        10.00,
        1
    );

    SET @VarianteB = CONVERT(INT, SCOPE_IDENTITY());

    -- La migracion 045 crea las existencias
    -- automaticamente al insertar variantes.

    IF (
        SELECT COUNT(*)
        FROM dbo.Existencias
        WHERE IDVariante IN (@VarianteA, @VarianteB)
    ) <> 2
        THROW 79003,
            'No se inicializaron las existencias.', 1;

    -- ==========================================
    -- 3. INGRESAR INVENTARIO CON KARDEX
    -- ==========================================

    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = @VarianteA,
        @IDUsuario = @IDAdmin,
        @TipoMovimiento = 'ENTRADA',
        @Cantidad = 10,
        @Motivo = N'Test 038 - entrada inicial A';

    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = @VarianteB,
        @IDUsuario = @IDAdmin,
        @TipoMovimiento = 'ENTRADA',
        @Cantidad = 10,
        @Motivo = N'Test 038 - entrada inicial B';

    -- ==========================================
    -- 4. DIRECCION Y CARRITO
    -- ==========================================

    INSERT INTO dbo.Direcciones (
        IDUsuario,
        Destinatario,
        Telefono,
        Departamento,
        Municipio,
        DireccionLinea1,
        Referencia
    )
    VALUES (
        @IDCliente,
        N'Cliente Test 038',
        N'55551234',
        N'Solola',
        N'Solola',
        N'Zona 1, direccion temporal',
        N'Prueba automatizada'
    );

    SET @IDDireccion =
        CONVERT(INT, SCOPE_IDENTITY());

    INSERT INTO dbo.Carritos (
        IDUsuario, Estado
    )
    VALUES (
        @IDCliente, 'ACTIVO'
    );

    SET @IDCarrito =
        CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.DetallesCarrito (
        IDCarrito,
        IDVariante,
        Cantidad
    )
    VALUES
        (@IDCarrito, @VarianteA, 3),
        (@IDCarrito, @VarianteB, 1);

    -- ==========================================
    -- 5. CREAR CUPON TEMPORAL Q3.33
    -- ==========================================

    INSERT INTO dbo.Cupones (
        Codigo,
        TipoDescuento,
        Valor,
        MontoMinimo,
        LimiteUsos,
        UsosRealizados,
        LimitePorCliente,
        FechaInicio,
        FechaFin,
        Activo
    )
    VALUES (
        @CodigoCupon,
        'MONTO_FIJO',
        3.33,
        0.00,
        5,
        0,
        2,
        DATEADD(DAY, -1, SYSUTCDATETIME()),
        DATEADD(DAY, 1, SYSUTCDATETIME()),
        1
    );

    -- ==========================================
    -- 6. RESERVAR Y CONFIRMAR CHECKOUT
    -- ==========================================

    EXEC dbo.SP_Inventario_ReservarExistencia
        @IDCarrito = @IDCarrito,
        @IDUsuario = @IDCliente,
        @IDReserva = @IDReserva OUTPUT;

    IF @IDReserva IS NULL
        THROW 79004,
            'No se creo la reserva.', 1;

    INSERT INTO @Compra
    EXEC dbo.SP_Pedidos_ConfirmarCheckout
        @IDUsuario = @IDCliente,
        @IDReserva = @IDReserva,
        @IDDireccion = @IDDireccion,
        @ClaveIdempotencia = @ClaveCheckout,
        @TotalEsperado = 40.00,
        @CodigoCupon = @CodigoCupon;

    SELECT @IDPedido = IDPedido
    FROM @Compra;

    IF @IDPedido IS NULL
        THROW 79005,
            'No se genero el pedido.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM @Compra
        WHERE Subtotal = 40.00
          AND Descuento = 3.33
          AND Total = 36.67
          AND Reutilizado = 0
    )
        THROW 79006,
            'El checkout calculo mal el descuento.', 1;

    PRINT 'OK: checkout Q40.00 - Q3.33 = Q36.67';

    SELECT @DetalleA = IDDetallePedido
    FROM dbo.DetallesPedido
    WHERE IDPedido = @IDPedido
      AND IDVariante = @VarianteA;

    SELECT @DetalleB = IDDetallePedido
    FROM dbo.DetallesPedido
    WHERE IDPedido = @IDPedido
      AND IDVariante = @VarianteB;

    IF @DetalleA IS NULL OR @DetalleB IS NULL
        THROW 79007,
            'Faltan detalles del pedido.', 1;

    -- ==========================================
    -- 7. ENTREGAR EL PEDIDO
    -- ==========================================

    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @IDPedido,
        @IDUsuario = @IDAdmin,
        @EstadoNuevo = 'PREPARANDO',
        @Observacion = N'Test 038';

    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @IDPedido,
        @IDUsuario = @IDAdmin,
        @EstadoNuevo = 'DESPACHADO',
        @Observacion = N'Test 038';

    EXEC dbo.SP_Pedidos_CambiarEstado
        @IDPedido = @IDPedido,
        @IDUsuario = @IDAdmin,
        @EstadoNuevo = 'ENTREGADO',
        @Observacion = N'Test 038';

    -- ==========================================
    -- 8. DEVOLVER UNA UNIDAD DEL PRODUCTO A
    -- Esperado: Q9.17
    -- ==========================================

    INSERT INTO @Devolucion1
    EXEC dbo.SP_Pedidos_RegistrarDevolucion
        @IDPedido = @IDPedido,
        @IDDetallePedido = @DetalleA,
        @IDUsuario = @IDCliente,
        @Cantidad = 1,
        @Motivo = N'Devolucion parcial de A',
        @ClaveIdempotencia = @Clave1;

    SELECT @Monto1 = MontoReembolso
    FROM @Devolucion1;

    IF @Monto1 <> 9.17
        THROW 79008,
            'Reembolso parcial incorrecto.', 1;

    PRINT 'OK: primera devolucion Q9.17';

    -- ==========================================
    -- 9. REPETIR SOLICITUD: IDEMPOTENCIA
    -- ==========================================

    INSERT INTO @Reintento
    EXEC dbo.SP_Pedidos_RegistrarDevolucion
        @IDPedido = @IDPedido,
        @IDDetallePedido = @DetalleA,
        @IDUsuario = @IDCliente,
        @Cantidad = 1,
        @Motivo = N'Devolucion parcial de A',
        @ClaveIdempotencia = @Clave1;

    IF NOT EXISTS (
        SELECT 1
        FROM @Devolucion1 a
        CROSS JOIN @Reintento r
        WHERE a.IDDevolucion = r.IDDevolucion
          AND r.Reutilizado = 1
          AND r.MontoReembolso = 9.17
    )
        THROW 79009,
            'Fallo la idempotencia.', 1;

    PRINT 'OK: reintento sin duplicar devolucion';

    -- ==========================================
    -- 10. DEVOLVER LAS OTRAS DOS UNIDADES A
    -- Esperado: Q18.33
    -- ==========================================

    INSERT INTO @Devolucion2
    EXEC dbo.SP_Pedidos_RegistrarDevolucion
        @IDPedido = @IDPedido,
        @IDDetallePedido = @DetalleA,
        @IDUsuario = @IDCliente,
        @Cantidad = 2,
        @Motivo = N'Devolucion restante de A',
        @ClaveIdempotencia = @Clave2;

    SELECT @Monto2 = MontoReembolso
    FROM @Devolucion2;

    IF @Monto2 <> 18.33
        THROW 79010,
            'Reembolso acumulado incorrecto.', 1;

    PRINT 'OK: segunda devolucion Q18.33';

    -- ==========================================
    -- 11. DEVOLVER PRODUCTO B
    -- Esperado: Q9.17
    -- ==========================================

    INSERT INTO @Devolucion3
    EXEC dbo.SP_Pedidos_RegistrarDevolucion
        @IDPedido = @IDPedido,
        @IDDetallePedido = @DetalleB,
        @IDUsuario = @IDCliente,
        @Cantidad = 1,
        @Motivo = N'Devolucion completa de B',
        @ClaveIdempotencia = @Clave3;

    SELECT @Monto3 = MontoReembolso
    FROM @Devolucion3;

    IF @Monto3 <> 9.17
        THROW 79011,
            'Reembolso de segunda linea incorrecto.', 1;

    PRINT 'OK: tercera devolucion Q9.17';

    -- ==========================================
    -- 12. REEMBOLSOS E INTEGRIDAD MONETARIA
    -- ==========================================

    SELECT
        @TotalReembolsado = SUM(MontoReembolso),
        @CantidadDevoluciones = COUNT(*)
    FROM dbo.Devoluciones
    WHERE IDPedido = @IDPedido;

    IF @TotalReembolsado <> 36.67
       OR @CantidadDevoluciones <> 3
        THROW 79012,
            'El reembolso total no coincide con el pago.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pedidos
        WHERE IDPedido = @IDPedido
          AND Estado = 'DEVUELTO_TOTAL'
          AND Total = 36.67
    )
        THROW 79013,
            'El estado o total del pedido es incorrecto.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Pagos
        WHERE IDPedido = @IDPedido
          AND Estado = 'REEMBOLSADO'
          AND Monto = 36.67
    )
        THROW 79014,
            'El pago no fue marcado como reembolsado.', 1;

    -- ==========================================
    -- 13. INVENTARIO Y KARDEX
    -- ==========================================

    IF (
        SELECT COUNT(*)
        FROM dbo.Existencias
        WHERE IDVariante IN (@VarianteA, @VarianteB)
          AND CantidadFisica = 10
    ) <> 2
        THROW 79015,
            'El inventario no regreso al saldo inicial.', 1;

    IF (
        SELECT COUNT(*)
        FROM dbo.MovimientosInventario
        WHERE TipoMovimiento = 'DEVOLUCION'
          AND IDVariante IN (@VarianteA, @VarianteB)
    ) <> 3
        THROW 79016,
            'Faltan movimientos de devolucion en el kardex.', 1;

    IF (
        SELECT ISNULL(SUM(CantidadFirmada), 0)
        FROM dbo.MovimientosInventario
        WHERE TipoMovimiento = 'DEVOLUCION'
          AND IDVariante IN (@VarianteA, @VarianteB)
    ) <> 4
        THROW 79017,
            'El kardex no reintegro las cuatro unidades.', 1;

    IF (
        SELECT COUNT(*)
        FROM dbo.HistorialEstadosPedido
        WHERE IDPedido = @IDPedido
          AND EstadoNuevo IN (
              'DEVUELTO_PARCIAL',
              'DEVUELTO_TOTAL'
          )
    ) <> 2
        THROW 79018,
            'El historial de estados es incorrecto.', 1;

    PRINT 'OK: inventario, kardex e historial coherentes';

    -- ==========================================
    -- 14. MOSTRAR RESULTADOS
    -- ==========================================

    SELECT
        @IDPedido AS IDPedidoTemporal,
        CAST(40.00 AS DECIMAL(19,2)) AS Subtotal,
        CAST(3.33 AS DECIMAL(19,2)) AS Descuento,
        CAST(36.67 AS DECIMAL(19,2)) AS TotalPagado,
        @Monto1 AS Reembolso1,
        @Monto2 AS Reembolso2,
        @Monto3 AS Reembolso3,
        @TotalReembolsado AS TotalReembolsado,
        'OK' AS Resultado;

    -- ==========================================
    -- 15. REVERTIR TODOS LOS CAMBIOS
    -- ==========================================

    ROLLBACK TRANSACTION;

    IF EXISTS (
        SELECT 1
        FROM dbo.Cupones
        WHERE Codigo = @CodigoCupon
    )
        THROW 79019,
            'El cupon temporal no fue revertido.', 1;

    IF EXISTS (
        SELECT 1
        FROM dbo.Usuarios
        WHERE Correo = @Correo
    )
        THROW 79020,
            'El cliente temporal no fue revertido.', 1;

    SELECT
        'OK: prueba de devoluciones con descuento'
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
