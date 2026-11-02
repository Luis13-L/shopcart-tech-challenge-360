USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 43
    )
        THROW 77201,
            'Primero ejecute la migracion 043.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 44
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Auth_CrearRefreshToken', N'P'
        ) IS NOT NULL
        OR OBJECT_ID(
            N'dbo.SP_Auth_RotarRefreshToken', N'P'
        ) IS NOT NULL
        OR OBJECT_ID(
            N'dbo.SP_Auth_RevocarRefreshToken', N'P'
        ) IS NOT NULL
            THROW 77202,
                'Existen procedimientos sin migracion registrada.',
                1;

        -- =====================================
        -- INDICE POR FAMILIA
        -- =====================================

        CREATE INDEX IX_RefreshTokens_Familia
        ON dbo.RefreshTokens (
            IDFamilia,
            RevocadoEn
        );

        -- =====================================
        -- 1. EMITIR REFRESH TOKEN
        -- =====================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Auth_CrearRefreshToken
    @IDUsuario INT,
    @TokenHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IDUsuario IS NULL OR @IDUsuario <= 0
       OR @TokenHash IS NULL
        THROW 77210,
            ''Parametros invalidos.'', 1;

    DECLARE @Familia UNIQUEIDENTIFIER = NEWID();
    DECLARE @Ahora DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @Expira DATETIME2(3) =
        DATEADD(DAY, 7, @Ahora);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios
            WHERE IDUsuario = @IDUsuario
              AND Activo = 1
        )
            THROW 77211,
                ''Usuario inexistente o inactivo.'',
                1;

        INSERT INTO dbo.RefreshTokens (
            IDUsuario,
            TokenHash,
            IDFamilia,
            FechaCreacion,
            ExpiraEn,
            RevocadoEn
        )
        VALUES (
            @IDUsuario,
            @TokenHash,
            @Familia,
            @Ahora,
            @Expira,
            NULL
        );

        COMMIT TRANSACTION;

        SELECT
            @IDUsuario AS IDUsuario,
            @Familia AS IDFamilia,
            @Expira AS ExpiraEn;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        -- =====================================
        -- 2. ROTAR REFRESH TOKEN
        -- =====================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Auth_RotarRefreshToken
    @TokenActualHash BINARY(32),
    @TokenNuevoHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @TokenActualHash IS NULL
       OR @TokenNuevoHash IS NULL
       OR @TokenActualHash = @TokenNuevoHash
        THROW 77212,
            ''Hashes de refresh invalidos.'', 1;

    DECLARE @IDUsuario INT;
    DECLARE @Familia UNIQUEIDENTIFIER;
    DECLARE @RevocadoEn DATETIME2(3);
    DECLARE @ExpiracionActual DATETIME2(3);
    DECLARE @Activo BIT;

    DECLARE @Correo NVARCHAR(254);
    DECLARE @NombreRol VARCHAR(30);

    DECLARE @Ahora DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @Expira DATETIME2(3) =
        DATEADD(DAY, 7, @Ahora);

    DECLARE @Codigo VARCHAR(20) = ''INVALIDO'';

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Bloquear el token utilizado.
        -- Las renovaciones simultaneas de un
        -- mismo token quedan serializadas.
        SELECT
            @IDUsuario = IDUsuario,
            @Familia = IDFamilia,
            @RevocadoEn = RevocadoEn,
            @ExpiracionActual = ExpiraEn
        FROM dbo.RefreshTokens WITH (
            UPDLOCK, HOLDLOCK
        )
        WHERE TokenHash = @TokenActualHash;

        IF @IDUsuario IS NULL
        BEGIN
            SET @Codigo = ''INVALIDO'';
        END
        ELSE IF @RevocadoEn IS NOT NULL
        BEGIN
            -- Reutilizacion de un token revocado:
            -- invalidar toda su familia.
            UPDATE dbo.RefreshTokens
            SET RevocadoEn = @Ahora
            WHERE IDFamilia = @Familia
              AND RevocadoEn IS NULL;

            SET @Codigo = ''REUTILIZADO'';
        END
        ELSE IF @ExpiracionActual <= @Ahora
        BEGIN
            UPDATE dbo.RefreshTokens
            SET RevocadoEn = @Ahora
            WHERE IDFamilia = @Familia
              AND RevocadoEn IS NULL;

            SET @Codigo = ''EXPIRADO'';
        END
        ELSE
        BEGIN
            SELECT
                @Activo = u.Activo,
                @Correo = u.Correo,
                @NombreRol = r.Nombre
            FROM dbo.Usuarios u
            INNER JOIN dbo.Roles r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuario;

            IF ISNULL(@Activo, 0) = 0
            BEGIN
                UPDATE dbo.RefreshTokens
                SET RevocadoEn = @Ahora
                WHERE IDFamilia = @Familia
                  AND RevocadoEn IS NULL;

                SET @Codigo = ''INACTIVO'';
            END
            ELSE
            BEGIN
                UPDATE dbo.RefreshTokens
                SET RevocadoEn = @Ahora
                WHERE TokenHash = @TokenActualHash
                  AND RevocadoEn IS NULL;

                IF @@ROWCOUNT <> 1
                    THROW 77213,
                        ''No se pudo revocar el token anterior.'',
                        1;

                INSERT INTO dbo.RefreshTokens (
                    IDUsuario,
                    TokenHash,
                    IDFamilia,
                    FechaCreacion,
                    ExpiraEn,
                    RevocadoEn
                )
                VALUES (
                    @IDUsuario,
                    @TokenNuevoHash,
                    @Familia,
                    @Ahora,
                    @Expira,
                    NULL
                );

                SET @Codigo = ''ROTADO'';
            END;
        END;

        COMMIT TRANSACTION;

        -- Devolver un codigo, en lugar de lanzar
        -- un error tras revocar una familia.
        -- Asi la revocacion no se revierte.
        SELECT
            @Codigo AS Codigo,
            CASE
                WHEN @Codigo = ''ROTADO''
                    THEN @IDUsuario
                ELSE NULL
            END AS IDUsuario,
            CASE
                WHEN @Codigo = ''ROTADO''
                    THEN @Correo
                ELSE NULL
            END AS Correo,
            CASE
                WHEN @Codigo = ''ROTADO''
                    THEN @NombreRol
                ELSE NULL
            END AS NombreRol,
            CASE
                WHEN @Codigo = ''ROTADO''
                    THEN @Expira
                ELSE NULL
            END AS ExpiraEn;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        -- =====================================
        -- 3. REVOCAR SESION
        -- =====================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Auth_RevocarRefreshToken
    @TokenHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @TokenHash IS NULL
        THROW 77214,
            ''Hash invalido.'', 1;

    DECLARE @Familia UNIQUEIDENTIFIER;
    DECLARE @Revocados INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @Familia = IDFamilia
        FROM dbo.RefreshTokens WITH (
            UPDLOCK, HOLDLOCK
        )
        WHERE TokenHash = @TokenHash;

        IF @Familia IS NOT NULL
        BEGIN
            UPDATE dbo.RefreshTokens
            SET RevocadoEn = SYSUTCDATETIME()
            WHERE IDFamilia = @Familia
              AND RevocadoEn IS NULL;

            SET @Revocados = @@ROWCOUNT;
        END;

        COMMIT TRANSACTION;

        SELECT @Revocados AS Revocados;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        -- =====================================
        -- 4. PERMISOS
        -- =====================================

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Auth_CrearRefreshToken
        TO [shopcart_api];

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Auth_RotarRefreshToken
        TO [shopcart_api];

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Auth_RevocarRefreshToken
        TO [shopcart_api];

        -- =====================================
        -- 5. REGISTRAR MIGRACION
        -- =====================================

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            44,
            N'044_RefreshTokenRotation'
        );

        PRINT 'Migracion 044 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Auth_CrearRefreshToken', N'P'
        ) IS NULL
        OR OBJECT_ID(
            N'dbo.SP_Auth_RotarRefreshToken', N'P'
        ) IS NULL
        OR OBJECT_ID(
            N'dbo.SP_Auth_RevocarRefreshToken', N'P'
        ) IS NULL
            THROW 77203,
                'Migracion registrada con procedimientos faltantes.',
                1;

        PRINT 'Migracion 044 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
