USE ShopCartDB;
GO

SET NOCOUNT ON;
GO

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 47
)
    THROW 78600,
        'Ejecute primero la migracion 047.', 1;

DECLARE @Cliente INT = (
    SELECT IDUsuario
    FROM dbo.Usuarios
    WHERE Correo = N'cliente.demo@shopcart.test'
      AND Activo = 1
);

DECLARE @Admin INT = (
    SELECT IDUsuario
    FROM dbo.Usuarios
    WHERE Correo = N'admin.demo@shopcart.test'
      AND Activo = 1
);

IF @Cliente IS NULL OR @Admin IS NULL
    THROW 78601,
        'Faltan cuentas demo.', 1;

-- 1. Listado del cliente.
EXEC dbo.SP_Pedidos_ListarPropios
    @IDUsuario = @Cliente,
    @Pagina = 1,
    @TamanoPagina = 10;

PRINT 'OK: consulta paginada ejecutada.';

-- 2. Consultar un pedido propio, si existe.
DECLARE @PedidoPropio BIGINT = (
    SELECT TOP (1) IDPedido
    FROM dbo.Pedidos
    WHERE IDUsuario = @Cliente
    ORDER BY IDPedido DESC
);

IF @PedidoPropio IS NOT NULL
BEGIN
    EXEC dbo.SP_Pedidos_ObtenerPropio
        @IDUsuario = @Cliente,
        @IDPedido = @PedidoPropio;

    PRINT 'OK: consulta de pedido propio.';
END
ELSE
    PRINT 'OMITIDO: cliente demo sin pedidos.';

-- 3. Intentar consultar un pedido ajeno.
DECLARE @PedidoAjeno BIGINT = (
    SELECT TOP (1) IDPedido
    FROM dbo.Pedidos
    WHERE IDUsuario <> @Cliente
    ORDER BY IDPedido DESC
);

IF @PedidoAjeno IS NOT NULL
BEGIN
    BEGIN TRY
        EXEC dbo.SP_Pedidos_ObtenerPropio
            @IDUsuario = @Cliente,
            @IDPedido = @PedidoAjeno;

        THROW 78602,
            'Fallo: se permitio consultar pedido ajeno.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 78521
            THROW;

        PRINT 'OK: pedido ajeno protegido.';
    END CATCH;
END
ELSE
    PRINT 'OMITIDO: no hay pedidos ajenos.';

-- 4. Administrador no usa consulta de cliente.
BEGIN TRY
    EXEC dbo.SP_Pedidos_ListarPropios
        @IDUsuario = @Admin;

    THROW 78603,
        'Fallo: administrador autorizado.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 78510
        THROW;

    PRINT 'OK: rol no permitido rechazado.';
END CATCH;

PRINT 'Pruebas de RF-07 finalizadas.';
GO
