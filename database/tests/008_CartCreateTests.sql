
USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDRol INT;
DECLARE @IDUsuario INT;

DECLARE @CarritoInvitado1 BIGINT;
DECLARE @CarritoInvitado2 BIGINT;
DECLARE @CarritoCliente1 BIGINT;
DECLARE @CarritoCliente2 BIGINT;

DECLARE @Token BINARY(32) =
    HASHBYTES(
        'SHA2_256',
        CONVERT(NVARCHAR(36), NEWID())
    );

DECLARE @Correo NVARCHAR(254) =
    CONCAT(
        N'qa-cart-sp-',
        CONVERT(NVARCHAR(36), NEWID()),
        N'@example.invalid'
    );

SELECT @IDRol = IDRol
FROM dbo.Roles
WHERE Nombre = 'Cliente';

IF @IDRol IS NULL
    THROW 57001, 'Falta el rol Cliente.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Crear cliente temporal
    INSERT INTO dbo.Usuarios (
        IDRol,
        Correo,
        PasswordHash,
        Activo
    )
    VALUES (
        @IDRol,
        @Correo,
        N'QA_NO_LOGIN',
        1
    );

    SET @IDUsuario = SCOPE_IDENTITY();

    -- ==================================
    -- PRUEBA 1: INVITADO
    -- ==================================
    EXEC dbo.SP_Carrito_Crear
        @TokenInvitadoHash = @Token,
        @IDCarrito = @CarritoInvitado1 OUTPUT;

    -- Repetir con el mismo token
    EXEC dbo.SP_Carrito_Crear
        @TokenInvitadoHash = @Token,
        @IDCarrito = @CarritoInvitado2 OUTPUT;

    -- ==================================
    -- PRUEBA 2: CLIENTE
    -- ==================================
    EXEC dbo.SP_Carrito_Crear
        @IDUsuario = @IDUsuario,
        @IDCarrito = @CarritoCliente1 OUTPUT;

    -- Repetir con el mismo usuario
    EXEC dbo.SP_Carrito_Crear
        @IDUsuario = @IDUsuario,
        @IDCarrito = @CarritoCliente2 OUTPUT;

    -- ==================================
    -- VERIFICACIONES
    -- ==================================
    IF @CarritoInvitado1 IS NULL
       OR @CarritoInvitado1 <> @CarritoInvitado2
        THROW 57002,
            'Se duplico el carrito invitado.',
            1;

    IF @CarritoCliente1 IS NULL
       OR @CarritoCliente1 <> @CarritoCliente2
        THROW 57003,
            'Se duplico el carrito del cliente.',
            1;

    IF @CarritoCliente1 = @CarritoInvitado1
        THROW 57004,
            'Los propietarios comparten carrito.',
            1;

    IF (
        SELECT COUNT(*)
        FROM dbo.Carritos
        WHERE IDUsuario = @IDUsuario
          AND Estado = 'ACTIVO'
    ) <> 1
        THROW 57005,
            'Cantidad incorrecta de carritos del cliente.',
            1;

    IF (
        SELECT COUNT(*)
        FROM dbo.Carritos
        WHERE TokenInvitadoHash = @Token
          AND Estado = 'ACTIVO'
    ) <> 1
        THROW 57006,
            'Cantidad incorrecta de carritos invitados.',
            1;

    SELECT
        'APROBADO' AS Resultado,
        @CarritoInvitado1 AS CarritoInvitado,
        @CarritoInvitado2 AS ReintentoInvitado,
        @CarritoCliente1 AS CarritoCliente,
        @CarritoCliente2 AS ReintentoCliente;

    -- Revertir todos los datos de prueba
    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

-- Verificar limpieza
SELECT
    CASE
        WHEN NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios
            WHERE Correo = @Correo
        )
        AND NOT EXISTS (
            SELECT 1
            FROM dbo.Carritos
            WHERE TokenInvitadoHash = @Token
        )
        THEN 'APROBADO'
        ELSE 'FALLO'
    END AS ResultadoLimpieza;
GO
