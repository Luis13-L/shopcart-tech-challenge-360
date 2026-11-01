USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDAdmin INT;
DECLARE @IDVariante INT = 4;

DECLARE @PrecioOriginal DECIMAL(19,2);
DECLARE @PrecioPrueba DECIMAL(19,2);

DECLARE @HistorialAntes INT;
DECLARE @AuditoriasAntes INT;

DECLARE @PedidosAntes NVARCHAR(MAX);
DECLARE @PedidosDespues NVARCHAR(MAX);

DECLARE @Motivo NVARCHAR(300) = CONCAT(
    N'TEST CAMBIO PRECIO ',
    CONVERT(NVARCHAR(36), NEWID())
);

-- ==========================================
-- 1. PRECONDICIONES
-- ==========================================

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 41
)
    THROW 75101,
        'Primero ejecute la migracion 041.', 1;

SELECT TOP (1)
    @IDAdmin = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Administrador'
  AND u.Activo = 1
ORDER BY u.IDUsuario;

IF @IDAdmin IS NULL
    THROW 75102,
        'No existe Administrador activo.', 1;

SELECT @PrecioOriginal = v.PrecioActual
FROM dbo.Variantes v
INNER JOIN dbo.Productos p
    ON p.IDProducto = v.IDProducto
WHERE v.IDVariante = @IDVariante
  AND v.Activa = 1
  AND p.Activo = 1;

IF @PrecioOriginal IS NULL
    THROW 75103,
        'La variante 4 no esta disponible.', 1;

-- Elegir un valor distinto y mayor que cero.
SET @PrecioPrueba =
    CASE
        WHEN @PrecioOriginal >= 2
            THEN @PrecioOriginal - 1
        ELSE @PrecioOriginal + 1
    END;

BEGIN TRY
    BEGIN TRANSACTION;

    SELECT @HistorialAntes = COUNT(*)
    FROM dbo.HistorialPreciosVariante
    WHERE IDVariante = @IDVariante;

    SELECT @AuditoriasAntes = COUNT(*)
    FROM dbo.BitacoraAuditoria
    WHERE Modulo = 'CATALOGO'
      AND Entidad = 'Variantes'
      AND IDEntidad =
          CONVERT(VARCHAR(40), @IDVariante)
      AND Accion = 'ACTUALIZAR';

    -- Guardar precios historicos de pedidos.
    SELECT @PedidosAntes = (
        SELECT
            IDDetallePedido,
            PrecioUnitario
        FROM dbo.DetallesPedido
        WHERE IDVariante = @IDVariante
        ORDER BY IDDetallePedido
        FOR JSON PATH
    );

    -- ======================================
    -- 2. ACTUALIZAR PRECIO
    -- ======================================

    EXEC dbo.SP_Catalogo_ActualizarPrecioVariante
        @IDUsuarioActor = @IDAdmin,
        @IDVariante = @IDVariante,
        @PrecioNuevo = @PrecioPrueba,
        @Motivo = @Motivo;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Variantes
        WHERE IDVariante = @IDVariante
          AND PrecioActual = @PrecioPrueba
    )
        THROW 75104,
            'El precio no se actualizo.', 1;

    -- ======================================
    -- 3. REINTENTO DEL MISMO PRECIO
    -- ======================================

    EXEC dbo.SP_Catalogo_ActualizarPrecioVariante
        @IDUsuarioActor = @IDAdmin,
        @IDVariante = @IDVariante,
        @PrecioNuevo = @PrecioPrueba,
        @Motivo = @Motivo;

    IF (
        SELECT COUNT(*)
        FROM dbo.HistorialPreciosVariante
        WHERE IDVariante = @IDVariante
    ) <> @HistorialAntes + 1
        THROW 75105,
            'Se duplico el historial de precios.', 1;

    IF (
        SELECT COUNT(*)
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND Entidad = 'Variantes'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDVariante)
          AND Accion = 'ACTUALIZAR'
    ) <> @AuditoriasAntes + 1
        THROW 75106,
            'Se duplico la auditoria.', 1;

    PRINT 'OK: cambio de precio sin duplicados.';

    -- ======================================
    -- 4. VALIDAR HISTORIAL Y AUDITORIA
    -- ======================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.HistorialPreciosVariante
        WHERE IDVariante = @IDVariante
          AND PrecioAnterior = @PrecioOriginal
          AND PrecioNuevo = @PrecioPrueba
          AND Motivo = @Motivo
          AND IDUsuario = @IDAdmin
    )
        THROW 75107,
            'El historial de precios es incorrecto.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND Entidad = 'Variantes'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDVariante)
          AND Accion = 'ACTUALIZAR'
          AND IDUsuario = @IDAdmin
          AND TRY_CONVERT(
              DECIMAL(19,2),
              JSON_VALUE(
                  ValoresNuevos, '$.precioActual'
              )
          ) = @PrecioPrueba
          AND JSON_VALUE(
              ValoresNuevos, '$.motivo'
          ) = @Motivo
    )
        THROW 75108,
            'La auditoria del precio es incorrecta.',
            1;

    PRINT 'OK: historial y auditoria correctos.';

    -- ======================================
    -- 5. COMPROBAR PEDIDOS HISTORICOS
    -- ======================================

    SELECT @PedidosDespues = (
        SELECT
            IDDetallePedido,
            PrecioUnitario
        FROM dbo.DetallesPedido
        WHERE IDVariante = @IDVariante
        ORDER BY IDDetallePedido
        FOR JSON PATH
    );

    IF @PedidosAntes <> @PedidosDespues
        THROW 75109,
            'Se alteraron precios historicos.',
            1;

    PRINT 'OK: pedidos historicos intactos.';

    SELECT
        IDVariante,
        PrecioAnterior,
        PrecioNuevo,
        IDUsuario,
        Motivo,
        FechaCambio
    FROM dbo.HistorialPreciosVariante
    WHERE Motivo = @Motivo;

    -- ======================================
    -- 6. ROLLBACK
    -- ======================================

    ROLLBACK TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Variantes
        WHERE IDVariante = @IDVariante
          AND PrecioActual = @PrecioOriginal
    )
        THROW 75110,
            'El precio original no se restauro.',
            1;

    IF EXISTS (
        SELECT 1
        FROM dbo.HistorialPreciosVariante
        WHERE Motivo = @Motivo
    )
        THROW 75111,
            'El historial de prueba persiste.',
            1;

    IF EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE JSON_VALUE(
            ValoresNuevos, '$.motivo'
        ) = @Motivo
    )
        THROW 75112,
            'La auditoria de prueba persiste.',
            1;

    SELECT
        'OK: actualizacion de precio validada'
            AS Resultado,
        'OK: ROLLBACK completo'
            AS Integridad;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
