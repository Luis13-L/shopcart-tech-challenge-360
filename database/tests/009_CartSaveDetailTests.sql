
USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDCliente INT;
DECLARE @IDOperador INT;
DECLARE @IDRolCliente INT;
DECLARE @IDRolOperador INT;
DECLARE @IDVariante INT;
DECLARE @IDCarrito BIGINT;
DECLARE @SaldoInicial INT;
DECLARE @CantidadFinal INT;
DECLARE @CantidadDetalles INT;

SELECT @IDRolCliente = IDRol
FROM dbo.Roles WHERE Nombre = 'Cliente';

SELECT @IDRolOperador = IDRol
FROM dbo.Roles WHERE Nombre = 'Operador';

SELECT @IDVariante = IDVariante
FROM dbo.Variantes WHERE SKU = N'BOT-500-NEG';

IF @IDRolCliente IS NULL
   OR @IDRolOperador IS NULL
   OR @IDVariante IS NULL
    THROW 59001, 'Faltan datos de prueba.', 1;

SELECT @SaldoInicial = CantidadFisica
FROM dbo.Existencias
WHERE IDVariante = @IDVariante;

IF @SaldoInicial IS NULL
    THROW 59002, 'Falta la existencia.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Crear cliente temporal
    INSERT INTO dbo.Usuarios (
        IDRol, Correo, PasswordHash
    )
    VALUES (
        @IDRolCliente,
        CONCAT(
            N'qa-cliente-',
            CONVERT(NVARCHAR(36), NEWID()),
            N'@example.invalid'
        ),
        N'QA_NO_LOGIN'
    );

    SET @IDCliente = SCOPE_IDENTITY();

    -- Crear operador temporal
    INSERT INTO dbo.Usuarios (
        IDRol, Correo, PasswordHash
    )
    VALUES (
        @IDRolOperador,
        CONCAT(
            N'qa-operador-',
            CONVERT(NVARCHAR(36), NEWID()),
            N'@example.invalid'
        ),
        N'QA_NO_LOGIN'
    );

    SET @IDOperador = SCOPE_IDENTITY();

    -- Preparar existencia suficiente
    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = @IDVariante,
        @IDUsuario = @IDOperador,
        @TipoMovimiento = 'ENTRADA',
        @Cantidad = 5,
        @Motivo = N'Preparacion de carrito QA';

    -- Crear carrito
    EXEC dbo.SP_Carrito_Crear
        @IDUsuario = @IDCliente,
        @IDCarrito = @IDCarrito OUTPUT;

    -- Primera solicitud: 2 unidades
    EXEC dbo.SP_Carrito_GuardarDetalle
        @IDCarrito = @IDCarrito,
        @IDVariante = @IDVariante,
        @Cantidad = 2,
        @IDUsuario = @IDCliente;

    -- Segunda solicitud: cantidad final 3
    EXEC dbo.SP_Carrito_GuardarDetalle
        @IDCarrito = @IDCarrito,
        @IDVariante = @IDVariante,
        @Cantidad = 3,
        @IDUsuario = @IDCliente;

    -- Reintento de la misma solicitud
    EXEC dbo.SP_Carrito_GuardarDetalle
        @IDCarrito = @IDCarrito,
        @IDVariante = @IDVariante,
        @Cantidad = 3,
        @IDUsuario = @IDCliente;

    SELECT
        @CantidadFinal = MAX(Cantidad),
        @CantidadDetalles = COUNT(*)
    FROM dbo.DetallesCarrito
    WHERE IDCarrito = @IDCarrito
      AND IDVariante = @IDVariante;

    SELECT
        CASE
            WHEN @CantidadFinal = 3
             AND @CantidadDetalles = 1
            THEN 'APROBADO'
            ELSE 'FALLO'
        END AS Resultado,
        @CantidadFinal AS CantidadFinal,
        @CantidadDetalles AS LineasRegistradas;

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

-- Confirmar restauracion del inventario
SELECT
    CASE
        WHEN CantidadFisica = @SaldoInicial
        THEN 'APROBADO'
        ELSE 'FALLO'
    END AS ResultadoRollback
FROM dbo.Existencias
WHERE IDVariante = @IDVariante;
GO
