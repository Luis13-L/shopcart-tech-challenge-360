
-- ==================================================
-- SHOPCART
-- PRUEBAS DE INTEGRIDAD DEL CARRITO
-- RF-04
-- ==================================================

USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @IDRol INT;
DECLARE @IDUsuario INT;
DECLARE @IDVariante INT;
DECLARE @IDCarrito BIGINT;
DECLARE @IDCarritoInvitado BIGINT;

DECLARE @Correo NVARCHAR(254) =
    CONCAT(
        N'qa-cart-',
        CONVERT(NVARCHAR(36), NEWID()),
        N'@example.invalid'
    );

DECLARE @Token BINARY(32) =
    HASHBYTES(
        'SHA2_256',
        CONVERT(NVARCHAR(36), NEWID())
    );

DECLARE @Resultados TABLE (
    Prueba NVARCHAR(100),
    Resultado VARCHAR(15),
    CodigoError INT NULL
);

-- Validar datos semilla
SELECT @IDRol = IDRol
FROM dbo.Roles
WHERE Nombre = 'Cliente';

SELECT @IDVariante = IDVariante
FROM dbo.Variantes
WHERE SKU = N'BOT-500-NEG';

IF @IDRol IS NULL OR @IDVariante IS NULL
    THROW 55001, 'Faltan datos semilla.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ======================================
    -- DATOS TEMPORALES
    -- ======================================

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

    -- Carrito de cliente autenticado
    INSERT INTO dbo.Carritos (IDUsuario)
    VALUES (@IDUsuario);

    SET @IDCarrito = SCOPE_IDENTITY();

    -- Carrito de invitado
    INSERT INTO dbo.Carritos (TokenInvitadoHash)
    VALUES (@Token);

    SET @IDCarritoInvitado = SCOPE_IDENTITY();

    -- Detalle valido
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

    -- ======================================
    -- PRUEBA 1: CARRITO SIN PROPIETARIO
    -- ======================================

    BEGIN TRY
        INSERT INTO dbo.Carritos (
            IDUsuario,
            TokenInvitadoHash
        )
        VALUES (NULL, NULL);

        INSERT INTO @Resultados
        VALUES ('Carrito sin propietario', 'FALLO', NULL);
    END TRY
    BEGIN CATCH
        INSERT INTO @Resultados
        VALUES (
            'Carrito sin propietario',
            CASE WHEN ERROR_NUMBER() = 547
                 THEN 'APROBADO' ELSE 'REVISAR' END,
            ERROR_NUMBER()
        );
    END CATCH;

    -- ======================================
    -- PRUEBA 2: CANTIDAD NEGATIVA
    -- ======================================

    BEGIN TRY
        INSERT INTO dbo.DetallesCarrito (
            IDCarrito,
            IDVariante,
            Cantidad
        )
        VALUES (
            @IDCarritoInvitado,
            @IDVariante,
            -5
        );

        INSERT INTO @Resultados
        VALUES ('Cantidad negativa', 'FALLO', NULL);
    END TRY
    BEGIN CATCH
        INSERT INTO @Resultados
        VALUES (
            'Cantidad negativa',
            CASE WHEN ERROR_NUMBER() = 547
                 THEN 'APROBADO' ELSE 'REVISAR' END,
            ERROR_NUMBER()
        );
    END CATCH;

    -- ======================================
    -- PRUEBA 3: VARIANTE DUPLICADA
    -- ======================================

    BEGIN TRY
        INSERT INTO dbo.DetallesCarrito (
            IDCarrito,
            IDVariante,
            Cantidad
        )
        VALUES (
            @IDCarrito,
            @IDVariante,
            2
        );

        INSERT INTO @Resultados
        VALUES ('Variante duplicada', 'FALLO', NULL);
    END TRY
    BEGIN CATCH
        INSERT INTO @Resultados
        VALUES (
            'Variante duplicada',
            CASE WHEN ERROR_NUMBER() IN (2601, 2627)
                 THEN 'APROBADO' ELSE 'REVISAR' END,
            ERROR_NUMBER()
        );
    END CATCH;

    -- ======================================
    -- PRUEBA 4: DOS CARRITOS ACTIVOS
    -- DEL MISMO USUARIO
    -- ======================================

    BEGIN TRY
        INSERT INTO dbo.Carritos (IDUsuario)
        VALUES (@IDUsuario);

        INSERT INTO @Resultados
        VALUES ('Dos carritos del usuario', 'FALLO', NULL);
    END TRY
    BEGIN CATCH
        INSERT INTO @Resultados
        VALUES (
            'Dos carritos del usuario',
            CASE WHEN ERROR_NUMBER() IN (2601, 2627)
                 THEN 'APROBADO' ELSE 'REVISAR' END,
            ERROR_NUMBER()
        );
    END CATCH;

    -- ======================================
    -- PRUEBA 5: TOKEN INVITADO DUPLICADO
    -- ======================================

    BEGIN TRY
        INSERT INTO dbo.Carritos (
            TokenInvitadoHash
        )
        VALUES (@Token);

        INSERT INTO @Resultados
        VALUES ('Token invitado duplicado', 'FALLO', NULL);
    END TRY
    BEGIN CATCH
        INSERT INTO @Resultados
        VALUES (
            'Token invitado duplicado',
            CASE WHEN ERROR_NUMBER() IN (2601, 2627)
                 THEN 'APROBADO' ELSE 'REVISAR' END,
            ERROR_NUMBER()
        );
    END CATCH;

    -- ======================================
    -- LIMPIEZA
    -- ======================================

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

-- Mostrar resultados
SELECT *
FROM @Resultados;

-- Confirmar limpieza
SELECT
    CASE
        WHEN NOT EXISTS (
            SELECT 1 FROM dbo.Usuarios
            WHERE Correo = @Correo
        )
        AND NOT EXISTS (
            SELECT 1 FROM dbo.Carritos
            WHERE TokenInvitadoHash = @Token
        )
        THEN 'APROBADO'
        ELSE 'FALLO'
    END AS ResultadoLimpieza;
GO
