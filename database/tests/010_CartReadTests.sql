
USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Cliente INT;
DECLARE @Operador INT;
DECLARE @Variante INT;
DECLARE @Carrito BIGINT;
DECLARE @SaldoInicial INT;

SELECT @Variante = IDVariante
FROM dbo.Variantes
WHERE SKU = N'BOT-500-NEG';

IF @Variante IS NULL
    THROW 61001, 'Falta variante de prueba.', 1;

SELECT @SaldoInicial = CantidadFisica
FROM dbo.Existencias
WHERE IDVariante = @Variante;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Cliente temporal
    INSERT INTO dbo.Usuarios (
        IDRol, Correo, PasswordHash
    )
    SELECT
        IDRol,
        CONCAT(
            N'qa-read-',
            CONVERT(NVARCHAR(36), NEWID()),
            N'@example.invalid'
        ),
        N'QA_NO_LOGIN'
    FROM dbo.Roles
    WHERE Nombre = 'Cliente';

    SET @Cliente = SCOPE_IDENTITY();

    -- Operador temporal
    INSERT INTO dbo.Usuarios (
        IDRol, Correo, PasswordHash
    )
    SELECT
        IDRol,
        CONCAT(
            N'qa-operator-',
            CONVERT(NVARCHAR(36), NEWID()),
            N'@example.invalid'
        ),
        N'QA_NO_LOGIN'
    FROM dbo.Roles
    WHERE Nombre = 'Operador';

    SET @Operador = SCOPE_IDENTITY();

    -- Preparar inventario temporal
    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = @Variante,
        @IDUsuario = @Operador,
        @TipoMovimiento = 'ENTRADA',
        @Cantidad = 5,
        @Motivo = N'Prueba de consulta del carrito';

    -- Crear carrito
    EXEC dbo.SP_Carrito_Crear
        @IDUsuario = @Cliente,
        @IDCarrito = @Carrito OUTPUT;

    -- Agregar tres unidades
    EXEC dbo.SP_Carrito_GuardarDetalle
        @IDCarrito = @Carrito,
        @IDVariante = @Variante,
        @Cantidad = 3,
        @IDUsuario = @Cliente;

    -- Consultar carrito y totales
    EXEC dbo.SP_Carrito_ObtenerDetalle
        @IDCarrito = @Carrito,
        @IDUsuario = @Cliente;

    -- No conservar datos de prueba
    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

-- Verificar restauracion
SELECT
    CASE
        WHEN CantidadFisica = @SaldoInicial
        THEN 'APROBADO'
        ELSE 'FALLO'
    END AS ResultadoRollback
FROM dbo.Existencias
WHERE IDVariante = @Variante;
GO
