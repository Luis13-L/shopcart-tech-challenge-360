
-- ================================================
-- SHOPCART - MIGRACION 010
-- Eliminar producto del carrito
-- ================================================

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
        WHERE Numero = 9
    )
        THROW 62001,
            'Primero debe ejecutar la migracion 009.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 10
    )
    BEGIN

        IF OBJECT_ID(
            N'dbo.SP_Carrito_EliminarProducto', N'P'
        ) IS NOT NULL
            THROW 62002,
                'Procedimiento existente sin migracion.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Carrito_EliminarProducto
    @IDCarrito BIGINT,
    @IDVariante INT,
    @IDUsuario INT = NULL,
    @TokenInvitadoHash BINARY(32) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FilasEliminadas INT = 0;

    IF @IDCarrito IS NULL OR @IDCarrito <= 0
        THROW 62003, ''Carrito invalido.'', 1;

    IF @IDVariante IS NULL OR @IDVariante <= 0
        THROW 62004, ''Variante invalida.'', 1;

    IF (
        @IDUsuario IS NULL
        AND @TokenInvitadoHash IS NULL
    ) OR (
        @IDUsuario IS NOT NULL
        AND @TokenInvitadoHash IS NOT NULL
    )
        THROW 62005,
            ''Debe indicar un unico propietario.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Validar propiedad y estado del carrito
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Carritos c WITH (UPDLOCK, HOLDLOCK)
            WHERE c.IDCarrito = @IDCarrito
              AND c.Estado = ''ACTIVO''
              AND (
                  (
                      @IDUsuario IS NOT NULL
                      AND c.IDUsuario = @IDUsuario
                      AND EXISTS (
                          SELECT 1
                          FROM dbo.Usuarios u
                          INNER JOIN dbo.Roles r
                              ON r.IDRol = u.IDRol
                          WHERE u.IDUsuario = @IDUsuario
                            AND u.Activo = 1
                            AND r.Nombre = ''Cliente''
                      )
                  )
                  OR (
                      @TokenInvitadoHash IS NOT NULL
                      AND c.TokenInvitadoHash =
                          @TokenInvitadoHash
                  )
              )
        )
            THROW 62006,
                ''Carrito inexistente o acceso denegado.'', 1;

        -- 2. Eliminar variante del carrito
        DELETE FROM dbo.DetallesCarrito
        WHERE IDCarrito = @IDCarrito
          AND IDVariante = @IDVariante;

        SET @FilasEliminadas = @@ROWCOUNT;

        -- 3. Actualizar actividad solo si hubo cambio
        IF @FilasEliminadas > 0
        BEGIN
            UPDATE dbo.Carritos
            SET UltimaActividad = SYSUTCDATETIME()
            WHERE IDCarrito = @IDCarrito;
        END;

        COMMIT TRANSACTION;

        SELECT
            @IDCarrito AS IDCarrito,
            @IDVariante AS IDVariante,
            CAST(
                CASE WHEN @FilasEliminadas > 0
                     THEN 1 ELSE 0 END
                AS BIT
            ) AS Eliminado;

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
            10,
            N'010_CartDeleteProcedure'
        );

        PRINT 'Migracion 010 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Carrito_EliminarProducto', N'P'
        ) IS NULL
            THROW 62007,
                'Migracion registrada sin procedimiento.', 1;

        PRINT 'Migracion 010 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
