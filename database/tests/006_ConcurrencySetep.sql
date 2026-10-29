
USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDVariante INT;
DECLARE @IDUsuario INT;
DECLARE @IDRol INT;
DECLARE @Saldo INT;

SELECT @IDVariante = IDVariante
FROM dbo.Variantes
WHERE SKU = N'BOT-500-NEG';

SELECT @IDRol = IDRol
FROM dbo.Roles
WHERE Nombre = 'Operador';

IF @IDVariante IS NULL OR @IDRol IS NULL
    THROW 53001, 'Faltan datos semilla.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    SELECT @Saldo = CantidadFisica
    FROM dbo.Existencias WITH (UPDLOCK, HOLDLOCK)
    WHERE IDVariante = @IDVariante;

    IF @Saldo IS NULL
        THROW 53002, 'No existe la fila de inventario.', 1;

    -- Usuario tecnico exclusivo para pruebas locales
    SELECT @IDUsuario = IDUsuario
    FROM dbo.Usuarios WITH (UPDLOCK, HOLDLOCK)
    WHERE Correo = N'qa-concurrencia@shopcart.invalid';

    IF @IDUsuario IS NULL
    BEGIN
        INSERT INTO dbo.Usuarios (
            IDRol,
            Correo,
            PasswordHash,
            Activo
        )
        VALUES (
            @IDRol,
            N'qa-concurrencia@shopcart.invalid',
            N'QA_NO_LOGIN',
            1
        );

        SET @IDUsuario = SCOPE_IDENTITY();
    END;

    -- Preparar exactamente una unidad
    IF @Saldo = 0
    BEGIN
        EXEC dbo.SP_Inventario_RegistrarMovimiento
            @IDVariante = @IDVariante,
            @IDUsuario = @IDUsuario,
            @TipoMovimiento = 'ENTRADA',
            @Cantidad = 1,
            @Motivo = N'Preparacion de prueba de concurrencia';
    END
    ELSE IF @Saldo <> 1
    BEGIN
        THROW 53003,
            'La prueba requiere un saldo inicial de 0 o 1.',
            1;
    END;

    COMMIT TRANSACTION;

    SELECT
        v.SKU,
        e.CantidadFisica,
        @IDUsuario AS IDUsuarioPrueba
    FROM dbo.Existencias e
    INNER JOIN dbo.Variantes v
        ON v.IDVariante = e.IDVariante
    WHERE e.IDVariante = @IDVariante;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
