
-- ===================================================
-- PROYECTO: ShopCart
-- MIGRACION: 007_CartCreateProcedure.sql
-- OBJETIVO: Crear u obtener carrito activo
-- ===================================================

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
        WHERE Numero = 6
    )
        THROW 56000,
            'Primero debe ejecutar la migracion 006.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 7
    )
    BEGIN

        IF OBJECT_ID(
            N'dbo.SP_Carrito_Crear', N'P'
        ) IS NOT NULL
            THROW 56006,
                'El procedimiento ya existe sin migracion registrada.',
                1;

        -- SQL dinamico utilizado solamente
        -- en el script de migracion.
        -- Los datos de negocio no se concatenan.
        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Carrito_Crear
    @IDUsuario INT = NULL,
    @TokenInvitadoHash BINARY(32) = NULL,
    @IDCarrito BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @IDCarrito = NULL;

    -- Debe existir exactamente un propietario
    IF (
        @IDUsuario IS NULL
        AND @TokenInvitadoHash IS NULL
    )
    OR (
        @IDUsuario IS NOT NULL
        AND @TokenInvitadoHash IS NOT NULL
    )
        THROW 56001,
            ''Debe indicar usuario o token, pero no ambos.'',
            1;

    IF @IDUsuario IS NOT NULL
       AND @IDUsuario <= 0
        THROW 56002,
            ''Identificador de usuario invalido.'',
            1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @IDUsuario IS NOT NULL
        BEGIN
            -- Solo clientes activos
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.Usuarios AS u
                INNER JOIN dbo.Roles AS r
                    ON r.IDRol = u.IDRol
                WHERE u.IDUsuario = @IDUsuario
                  AND u.Activo = 1
                  AND r.Nombre = ''Cliente''
            )
                THROW 56003,
                    ''Usuario no autorizado para carrito.'',
                    1;

            -- Buscar carrito activo con bloqueo
            SELECT @IDCarrito = IDCarrito
            FROM dbo.Carritos WITH (
                UPDLOCK,
                HOLDLOCK
            )
            WHERE IDUsuario = @IDUsuario
              AND Estado = ''ACTIVO'';

            IF @IDCarrito IS NULL
            BEGIN
                INSERT INTO dbo.Carritos (
                    IDUsuario,
                    Estado
                )
                VALUES (
                    @IDUsuario,
                    ''ACTIVO''
                );

                SET @IDCarrito =
                    CONVERT(BIGINT, SCOPE_IDENTITY());
            END;
        END
        ELSE
        BEGIN
            -- Buscar carrito del invitado
            SELECT @IDCarrito = IDCarrito
            FROM dbo.Carritos WITH (
                UPDLOCK,
                HOLDLOCK
            )
            WHERE TokenInvitadoHash =
                @TokenInvitadoHash
              AND Estado = ''ACTIVO'';

            IF @IDCarrito IS NULL
            BEGIN
                INSERT INTO dbo.Carritos (
                    TokenInvitadoHash,
                    Estado
                )
                VALUES (
                    @TokenInvitadoHash,
                    ''ACTIVO''
                );

                SET @IDCarrito =
                    CONVERT(BIGINT, SCOPE_IDENTITY());
            END;
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            7,
            N'007_CartCreateProcedure'
        );

        PRINT 'Migracion 007 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Carrito_Crear', N'P'
        ) IS NULL
            THROW 56007,
                'Migracion registrada, pero falta el procedimiento.',
                1;

        PRINT 'Migracion 007 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
