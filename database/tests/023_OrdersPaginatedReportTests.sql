USE ShopCartDB;
GO

SET NOCOUNT ON;

DECLARE @IDAdmin INT;

SELECT TOP (1)
    @IDAdmin = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Administrador'
  AND u.Activo = 1
ORDER BY u.IDUsuario;

IF @IDAdmin IS NULL
    THROW 72120,
        'No existe Administrador activo.', 1;

-- ==========================================
-- PRUEBA 1: TODOS LOS PEDIDOS
-- ==========================================

PRINT 'PRUEBA 1: Listado general';

EXEC dbo.SP_Reportes_ListarPedidos
    @IDUsuario = @IDAdmin,
    @Pagina = 1,
    @TamanoPagina = 10;

-- ==========================================
-- PRUEBA 2: PEDIDOS ENTREGADOS
-- ==========================================

PRINT 'PRUEBA 2: Filtro por estado';

EXEC dbo.SP_Reportes_ListarPedidos
    @IDUsuario = @IDAdmin,
    @Estado = 'ENTREGADO',
    @Pagina = 1,
    @TamanoPagina = 10;

-- ==========================================
-- PRUEBA 3: FILTRO POR CLIENTE
-- ==========================================

PRINT 'PRUEBA 3: Filtro por cliente';

EXEC dbo.SP_Reportes_ListarPedidos
    @IDUsuario = @IDAdmin,
    @IDCliente = 12,
    @Pagina = 1,
    @TamanoPagina = 10;

-- ==========================================
-- PRUEBA 4: FILTRO POR FECHAS
-- ==========================================

PRINT 'PRUEBA 4: Rango de fechas UTC';

EXEC dbo.SP_Reportes_ListarPedidos
    @IDUsuario = @IDAdmin,
    @FechaInicio = '2026-10-01',
    @FechaFin = '2026-11-30',
    @Pagina = 1,
    @TamanoPagina = 10;

-- ==========================================
-- PRUEBA 5: PAGINACION
-- ==========================================

PRINT 'PRUEBA 5: Primera pagina';

EXEC dbo.SP_Reportes_ListarPedidos
    @IDUsuario = @IDAdmin,
    @Pagina = 1,
    @TamanoPagina = 2;

PRINT 'PRUEBA 6: Segunda pagina';

EXEC dbo.SP_Reportes_ListarPedidos
    @IDUsuario = @IDAdmin,
    @Pagina = 2,
    @TamanoPagina = 2;
GO
