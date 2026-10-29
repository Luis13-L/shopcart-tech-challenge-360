
USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDCliente INT;
DECLARE @IDVariante INT;
DECLARE @IDCarrito BIGINT;
DECLARE @LineasRestantes INT;
DECLARE @SaldoAntes INT;

SELECT @IDVariante = IDVariante
FROM dbo.Variantes
WHERE SKU = N'BOT-500-NEG';

IF @IDVariante IS NULL
    THROW 63001, 'Falta variante de prueba.', 1;

SELECT @SaldoAntes = CantidadFisica
FROM dbo.Existencias
WHERE IDVariante = @IDVariante;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Crear cliente temporal
    INSERT INTO dbo.Usuarios (
        IDRol,
        Correo,
        PasswordHash
    )
    SELECT
        IDRol,
        CONCAT(
            N'qa-delete-',
            CONVERT(NVARCHAR(36), NEWID()),
            N'@example.invalid'
        ),
        N'QA_NO_LOGIN'
    FROM dbo.Roles
    WHERE Nombre = 'Cliente';

    SET @IDCliente = SCOPE_IDENTITY();

    IF @IDCliente IS NULL
        THROW 63002, 'No se creo cliente.', 1;

    -- Crear carrito
    EXEC dbo.SP_Carrito_Crear
        @IDUsuario = @IDCliente,
        @IDCarrito = @IDCarrito OUTPUT;

    -- Insertar detalle temporal
    INSERT INTO dbo.DetallesCarrito (
        IDCarrito,
        IDVariante,
        Cantidad
    )
    VALUES (
        @IDCarrito,
        @IDVariante,
        1
    );

    -- Primera eliminacion
    EXEC dbo.SP_Carrito_EliminarProducto
        @IDCarrito = @IDCarrito,
        @IDVariante = @IDVariante,
        @IDUsuario = @IDCliente;

    -- Reintento de eliminacion
    EXEC dbo.SP_Carrito_EliminarProducto
        @IDCarrito = @IDCarrito,
        @IDVariante = @IDVariante,
        @IDUsuario = @IDCliente;

    -- Verificar resultado
    SELECT @LineasRestantes = COUNT(*)
    FROM dbo.DetallesCarrito
    WHERE IDCarrito = @IDCarrito;

    IF @LineasRestantes <> 0
        THROW 63003,
            'El producto no fue eliminado.', 1;

    IF (
        SELECT CantidadFisica
        FROM dbo.Existencias
        WHERE IDVariante = @IDVariante
    ) <> @SaldoAntes
        THROW 63004,
            'El inventario fue modificado.', 1;

    SELECT
        'APROBADO' AS Resultado,
        @LineasRestantes AS LineasRestantes,
        'Inventario sin cambios' AS VerificacionInventario;

    -- Deshacer los datos de prueba
    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
