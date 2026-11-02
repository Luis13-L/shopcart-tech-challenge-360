USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDAdmin INT;
DECLARE @IDCategoria INT;
DECLARE @IDProducto INT;
DECLARE @IDVariante INT;

DECLARE @SKU NVARCHAR(64) = CONCAT(
    N'INVTEST-',
    REPLACE(
        CONVERT(NVARCHAR(36), NEWID()),
        N'-', N''
    )
);

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 45
)
    THROW 78101,
        'Primero ejecute la migracion 045.', 1;

SELECT TOP (1)
    @IDAdmin = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE u.Activo = 1
  AND r.Nombre = 'Administrador'
ORDER BY u.IDUsuario;

SELECT TOP (1)
    @IDCategoria = IDCategoria
FROM dbo.Categorias
WHERE Activa = 1
ORDER BY IDCategoria;

IF @IDAdmin IS NULL OR @IDCategoria IS NULL
    THROW 78102,
        'Falta administrador o categoria activa.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Crear mediante el SP real del catalogo.
    EXEC dbo.SP_Catalogo_CrearProducto
        @IDUsuarioActor = @IDAdmin,
        @IDCategoria = @IDCategoria,
        @Nombre = N'Producto prueba inventario',
        @Descripcion = N'Validacion de migracion 045',
        @SKU = @SKU,
        @PrecioActual = 125.00;

    SELECT
        @IDProducto = p.IDProducto,
        @IDVariante = v.IDVariante
    FROM dbo.Variantes v
    INNER JOIN dbo.Productos p
        ON p.IDProducto = v.IDProducto
    WHERE v.SKU = @SKU;

    IF @IDProducto IS NULL OR @IDVariante IS NULL
        THROW 78103,
            'No se creo producto y variante.', 1;

    -- Debe existir exactamente una fila
    -- de inventario inicial con saldo cero.
    IF (
        SELECT COUNT(*)
        FROM dbo.Existencias
        WHERE IDVariante = @IDVariante
          AND CantidadFisica = 0
    ) <> 1
        THROW 78104,
            'La variante no tiene inventario inicial.', 1;

    SELECT
        v.IDVariante,
        v.SKU,
        e.CantidadFisica,
        'OK: inventario inicial creado'
            AS Resultado
    FROM dbo.Variantes v
    INNER JOIN dbo.Existencias e
        ON e.IDVariante = v.IDVariante
    WHERE v.IDVariante = @IDVariante;

    ROLLBACK TRANSACTION;

    -- Nada de la prueba debe persistir.
    IF EXISTS (
        SELECT 1
        FROM dbo.Variantes
        WHERE SKU = @SKU
    )
        THROW 78105,
            'La variante de prueba persiste.', 1;

    IF EXISTS (
        SELECT 1
        FROM dbo.Existencias
        WHERE IDVariante = @IDVariante
    )
        THROW 78106,
            'El inventario de prueba persiste.', 1;

    SELECT
        'OK: inicializacion de inventario validada'
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
