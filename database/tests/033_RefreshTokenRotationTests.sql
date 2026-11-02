USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IDCliente INT;

DECLARE @HashA BINARY(32) =
    HASHBYTES(
        'SHA2_256',
        CONVERT(NVARCHAR(36), NEWID())
    );

DECLARE @HashB BINARY(32) =
    HASHBYTES(
        'SHA2_256',
        CONVERT(NVARCHAR(36), NEWID())
    );

DECLARE @HashC BINARY(32) =
    HASHBYTES(
        'SHA2_256',
        CONVERT(NVARCHAR(36), NEWID())
    );

DECLARE @HashLogout BINARY(32) =
    HASHBYTES(
        'SHA2_256',
        CONVERT(NVARCHAR(36), NEWID())
    );

DECLARE @Familia UNIQUEIDENTIFIER;

DECLARE @Rotacion TABLE (
    Codigo VARCHAR(20),
    IDUsuario INT NULL,
    Correo NVARCHAR(254) NULL,
    NombreRol VARCHAR(30) NULL,
    ExpiraEn DATETIME2(3) NULL
);

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 44
)
    THROW 77301,
        'Primero ejecute la migracion 044.', 1;

SELECT TOP (1)
    @IDCliente = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Cliente'
  AND u.Activo = 1
ORDER BY u.IDUsuario DESC;

IF @IDCliente IS NULL
    THROW 77302,
        'No existe un Cliente activo.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ======================================
    -- 1. EMITIR TOKEN A
    -- ======================================

    EXEC dbo.SP_Auth_CrearRefreshToken
        @IDUsuario = @IDCliente,
        @TokenHash = @HashA;

    SELECT @Familia = IDFamilia
    FROM dbo.RefreshTokens
    WHERE TokenHash = @HashA;

    IF @Familia IS NULL
        THROW 77303,
            'No se creo el token inicial.', 1;

    PRINT 'OK: refresh token emitido.';

    -- ======================================
    -- 2. ROTAR A -> B
    -- ======================================

    INSERT INTO @Rotacion
    EXEC dbo.SP_Auth_RotarRefreshToken
        @TokenActualHash = @HashA,
        @TokenNuevoHash = @HashB;

    IF NOT EXISTS (
        SELECT 1 FROM @Rotacion
        WHERE Codigo = 'ROTADO'
          AND IDUsuario = @IDCliente
          AND NombreRol = 'Cliente'
    )
        THROW 77304,
            'La rotacion no devolvio ROTADO.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.RefreshTokens
        WHERE TokenHash = @HashA
          AND RevocadoEn IS NOT NULL
    )
        THROW 77305,
            'El token anterior sigue activo.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.RefreshTokens
        WHERE TokenHash = @HashB
          AND IDFamilia = @Familia
          AND RevocadoEn IS NULL
    )
        THROW 77306,
            'El nuevo token no esta activo.', 1;

    PRINT 'OK: rotacion A a B.';

    -- ======================================
    -- 3. REUTILIZAR TOKEN A
    -- ======================================

    DELETE FROM @Rotacion;

    INSERT INTO @Rotacion
    EXEC dbo.SP_Auth_RotarRefreshToken
        @TokenActualHash = @HashA,
        @TokenNuevoHash = @HashC;

    IF NOT EXISTS (
        SELECT 1 FROM @Rotacion
        WHERE Codigo = 'REUTILIZADO'
    )
        THROW 77307,
            'No se detecto la reutilizacion.', 1;

    IF EXISTS (
        SELECT 1
        FROM dbo.RefreshTokens
        WHERE IDFamilia = @Familia
          AND RevocadoEn IS NULL
    )
        THROW 77308,
            'La familia sigue activa tras reutilizacion.',
            1;

    PRINT 'OK: reutilizacion detectada y familia revocada.';

    -- ======================================
    -- 4. PROBAR CIERRE DE SESION
    -- ======================================

    EXEC dbo.SP_Auth_CrearRefreshToken
        @IDUsuario = @IDCliente,
        @TokenHash = @HashLogout;

    EXEC dbo.SP_Auth_RevocarRefreshToken
        @TokenHash = @HashLogout;

    IF EXISTS (
        SELECT 1
        FROM dbo.RefreshTokens
        WHERE TokenHash = @HashLogout
          AND RevocadoEn IS NULL
    )
        THROW 77309,
            'El logout no revoco el token.', 1;

    PRINT 'OK: revocacion de sesion.';

    -- ======================================
    -- 5. MOSTRAR ESTADO
    -- ======================================

    SELECT
        IDUsuario,
        IDFamilia,
        FechaCreacion,
        ExpiraEn,
        CASE
            WHEN RevocadoEn IS NULL
                THEN 'ACTIVO'
            ELSE 'REVOCADO'
        END AS Estado
    FROM dbo.RefreshTokens
    WHERE TokenHash IN (
        @HashA,
        @HashB,
        @HashLogout
    )
    ORDER BY IDRefreshToken;

    -- ======================================
    -- 6. REVERTIR PRUEBA
    -- ======================================

    ROLLBACK TRANSACTION;

    IF EXISTS (
        SELECT 1
        FROM dbo.RefreshTokens
        WHERE TokenHash IN (
            @HashA,
            @HashB,
            @HashC,
            @HashLogout
        )
    )
        THROW 77310,
            'Los tokens de prueba persisten.', 1;

    SELECT
        'OK: rotacion y revocacion validadas'
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
