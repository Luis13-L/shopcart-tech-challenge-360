USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDAdmin INT;
DECLARE @IDCategoria INT;
DECLARE @IDProducto INT;
DECLARE @IDVariante INT;

DECLARE @SKU NVARCHAR(64) = CONCAT(
    N'AUD-',
    REPLACE(
        CONVERT(NVARCHAR(36), NEWID()),
        N'-',
        N''
    )
);

DECLARE @NombreInicial NVARCHAR(200) =
    N'Producto prueba auditoria';

DECLARE @NombreNuevo NVARCHAR(200) =
    N'Producto auditoria actualizado';

-- ==========================================
-- 1. PRECONDICIONES
-- ==========================================

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 40
)
    THROW 74101,
        'Primero ejecute la migracion 040.',
        1;

SELECT TOP (1)
    @IDAdmin = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Administrador'
  AND u.Activo = 1
ORDER BY u.IDUsuario;

SELECT TOP (1)
    @IDCategoria = IDCategoria
FROM dbo.Categorias
WHERE Activa = 1
ORDER BY IDCategoria;

IF @IDAdmin IS NULL
    THROW 74102,
        'No existe Administrador activo.', 1;

IF @IDCategoria IS NULL
    THROW 74103,
        'No existe categoria activa.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ======================================
    -- 2. CREAR PRODUCTO
    -- ======================================

    EXEC dbo.SP_Catalogo_CrearProducto
        @IDUsuarioActor = @IDAdmin,
        @IDCategoria = @IDCategoria,
        @Nombre = @NombreInicial,
        @Descripcion = N'Prueba de auditoria',
        @SKU = @SKU,
        @PrecioActual = 150.00;

    SELECT
        @IDProducto = p.IDProducto,
        @IDVariante = v.IDVariante
    FROM dbo.Productos p
    INNER JOIN dbo.Variantes v
        ON v.IDProducto = p.IDProducto
    WHERE v.SKU = @SKU;

    IF @IDProducto IS NULL
       OR @IDVariante IS NULL
        THROW 74104,
            'No se creo el producto o variante.',
            1;

    -- Auditoria del producto creado
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND Entidad = 'Productos'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDProducto)
          AND Accion = 'CREAR'
          AND IDUsuario = @IDAdmin
          AND JSON_VALUE(
              ValoresNuevos,
              '$.Nombre'
          ) = @NombreInicial
    )
        THROW 74105,
            'Falta auditoria CREAR producto.',
            1;

    -- Auditoria de la variante creada
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND Entidad = 'Variantes'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDVariante)
          AND Accion = 'CREAR'
          AND JSON_VALUE(
              ValoresNuevos,
              '$.PrecioActual'
          ) = '150.00'
    )
        THROW 74106,
            'Falta auditoria CREAR variante.',
            1;

    PRINT 'OK: creacion de producto y variante auditada.';

    -- ======================================
    -- 3. ACTUALIZAR PRODUCTO
    -- ======================================

    EXEC dbo.SP_Catalogo_ActualizarProducto
        @IDUsuarioActor = @IDAdmin,
        @IDProducto = @IDProducto,
        @Nombre = @NombreNuevo;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND Entidad = 'Productos'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDProducto)
          AND Accion = 'ACTUALIZAR'
          AND JSON_VALUE(
              ValoresAnteriores,
              '$.Nombre'
          ) = @NombreInicial
          AND JSON_VALUE(
              ValoresNuevos,
              '$.Nombre'
          ) = @NombreNuevo
    )
        THROW 74107,
            'Falta auditoria ACTUALIZAR producto.',
            1;

    PRINT 'OK: actualizacion auditada.';

    -- ======================================
    -- 4. DESACTIVAR PRODUCTO
    -- ======================================

    EXEC dbo.SP_Catalogo_DesactivarProducto
        @IDUsuarioActor = @IDAdmin,
        @IDProducto = @IDProducto;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Productos
        WHERE IDProducto = @IDProducto
          AND Activo = 0
    )
        THROW 74108,
            'El producto sigue activo.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Variantes
        WHERE IDVariante = @IDVariante
          AND Activa = 0
    )
        THROW 74109,
            'La variante sigue activa.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND Entidad = 'Productos'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDProducto)
          AND Accion = 'DESACTIVAR'
          AND JSON_VALUE(
              ValoresAnteriores,
              '$.Activo'
          ) = 'true'
          AND JSON_VALUE(
              ValoresNuevos,
              '$.Activo'
          ) = 'false'
    )
        THROW 74110,
            'Falta auditoria DESACTIVAR producto.',
            1;

    PRINT 'OK: desactivacion auditada.';

    -- ======================================
    -- 5. COMPROBAR CUATRO EVENTOS
    -- ======================================

    IF (
        SELECT COUNT(*)
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND (
              (
                  Entidad = 'Productos'
                  AND IDEntidad =
                      CONVERT(VARCHAR(40), @IDProducto)
              )
              OR (
                  Entidad = 'Variantes'
                  AND IDEntidad =
                      CONVERT(VARCHAR(40), @IDVariante)
              )
          )
    ) <> 4
        THROW 74111,
            'Cantidad de eventos incorrecta.',
            1;

    SELECT
        IDBitacora,
        IDUsuario,
        Modulo,
        Entidad,
        IDEntidad,
        Accion,
        ValoresAnteriores,
        ValoresNuevos
    FROM dbo.BitacoraAuditoria
    WHERE Modulo = 'CATALOGO'
      AND (
          (
              Entidad = 'Productos'
              AND IDEntidad =
                  CONVERT(VARCHAR(40), @IDProducto)
          )
          OR (
              Entidad = 'Variantes'
              AND IDEntidad =
                  CONVERT(VARCHAR(40), @IDVariante)
          )
      )
    ORDER BY IDBitacora;

    PRINT 'OK: cuatro eventos de auditoria correctos.';

    -- ======================================
    -- 6. REVERTIR PRUEBA
    -- ======================================

    ROLLBACK TRANSACTION;

    IF EXISTS (
        SELECT 1
        FROM dbo.Productos
        WHERE IDProducto = @IDProducto
    )
        THROW 74112,
            'Producto de prueba no revertido.',
            1;

    IF EXISTS (
        SELECT 1
        FROM dbo.Variantes
        WHERE IDVariante = @IDVariante
    )
        THROW 74113,
            'Variante de prueba no revertida.',
            1;

    IF EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND Entidad = 'Productos'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDProducto)
    )
        THROW 74114,
            'Auditoria de prueba no revertida.',
            1;

    SELECT
        'OK: auditoria del catalogo validada'
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
