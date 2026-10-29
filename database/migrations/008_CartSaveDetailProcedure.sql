
-- ================================================
-- SHOPCART - MIGRACION 008
-- Crear o actualizar detalle de carrito
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
        WHERE Numero = 7
    )
        THROW 58001,
            'Primero debe ejecutar la migracion 007.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 8
    )
    BEGIN

        IF OBJECT_ID(
            N'dbo.SP_Carrito_GuardarDetalle', N'P'
        ) IS NOT NULL
            THROW 58002,
                'Procedimiento existente sin migracion registrada.',
                1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Carrito_GuardarDetalle
    @IDCarrito BIGINT,
    @IDVariante INT,
    @Cantidad INT,
    @IDUsuario INT = NULL,
    @TokenInvitadoHash BINARY(32) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CarritoValido BIGINT;
    DECLARE @IDDetalle BIGINT;
    DECLARE @ExistenciaFisica INT;
    DECLARE @Fecha DATETIME2(3);

    -- Validar parametros
    IF @IDCarrito IS NULL OR @IDCarrito <= 0
        THROW 58003, ''Carrito invalido.'', 1;

    IF @IDVariante IS NULL OR @IDVariante <= 0
        THROW 58004, ''Variante invalida.'', 1;

    IF @Cantidad IS NULL OR @Cantidad <= 0
        THROW 58005, ''La cantidad debe ser positiva.'', 1;

    -- Exactamente un identificador de propietario
    IF (
        @IDUsuario IS NULL
        AND @TokenInvitadoHash IS NULL
    )
    OR (
        @IDUsuario IS NOT NULL
        AND @TokenInvitadoHash IS NOT NULL
    )
        THROW 58006,
            ''Debe indicar un unico propietario.'',
            1;

    BEGIN TRY
        BEGIN TRANSACTION;

        SET @Fecha = SYSUTCDATETIME();

        -- 1. Validar propietario y bloquear carrito
        SELECT @CarritoValido = c.IDCarrito
        FROM dbo.Carritos AS c WITH (UPDLOCK, HOLDLOCK)
        WHERE c.IDCarrito = @IDCarrito
          AND c.Estado = ''ACTIVO''
          AND (
              (
                  @IDUsuario IS NOT NULL
                  AND c.IDUsuario = @IDUsuario
              )
              OR
              (
                  @TokenInvitadoHash IS NOT NULL
                  AND c.TokenInvitadoHash =
                      @TokenInvitadoHash
              )
          );

        IF @CarritoValido IS NULL
            THROW 58007,
                ''Carrito inexistente o sin autorizacion.'',
                1;

        -- 2. Validar cliente autenticado
        IF @IDUsuario IS NOT NULL
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.Usuarios AS u
                INNER JOIN dbo.Roles AS r
                    ON r.IDRol = u.IDRol
                WHERE u.IDUsuario = @IDUsuario
                  AND u.Activo = 1
                  AND r.Nombre = ''Cliente''
            )
                THROW 58008,
                    ''Cliente inactivo o no autorizado.'',
                    1;
        END;

        -- 3. Validar variante y existencia
        SELECT
            @ExistenciaFisica = e.CantidadFisica
        FROM dbo.Existencias AS e
            WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.Variantes AS v
            ON v.IDVariante = e.IDVariante
        INNER JOIN dbo.Productos AS p
            ON p.IDProducto = v.IDProducto
        INNER JOIN dbo.Categorias AS c
            ON c.IDCategoria = p.IDCategoria
        WHERE e.IDVariante = @IDVariante
          AND v.Activa = 1
          AND p.Activo = 1
          AND c.Activa = 1;

        IF @ExistenciaFisica IS NULL
            THROW 58009,
                ''Variante no disponible o sin existencia registrada.'',
                1;

        -- VALIDACION PROVISIONAL:
        -- Todavia no existen reservas de checkout.
        -- Se ampliara para calcular:
        -- fisica - reservas vigentes.
        IF @Cantidad > @ExistenciaFisica
            THROW 58010,
                ''Cantidad superior a la existencia fisica.'',
                1;

        -- 4. Buscar detalle existente
        SELECT @IDDetalle = IDDetalleCarrito
        FROM dbo.DetallesCarrito WITH (UPDLOCK, HOLDLOCK)
        WHERE IDCarrito = @IDCarrito
          AND IDVariante = @IDVariante;

        IF @IDDetalle IS NULL
        BEGIN
            INSERT INTO dbo.DetallesCarrito (
                IDCarrito,
                IDVariante,
                Cantidad,
                FechaActualizacion
            )
            VALUES (
                @IDCarrito,
                @IDVariante,
                @Cantidad,
                @Fecha
            );

            SET @IDDetalle =
                CONVERT(BIGINT, SCOPE_IDENTITY());
        END
        ELSE
        BEGIN
            UPDATE dbo.DetallesCarrito
            SET Cantidad = @Cantidad,
                FechaActualizacion = @Fecha
            WHERE IDDetalleCarrito = @IDDetalle;
        END;

        -- 5. Actualizar actividad
        UPDATE dbo.Carritos
        SET UltimaActividad = @Fecha
        WHERE IDCarrito = @IDCarrito;

        COMMIT TRANSACTION;

        SELECT
            @IDDetalle AS IDDetalleCarrito,
            @IDCarrito AS IDCarrito,
            @IDVariante AS IDVariante,
            @Cantidad AS Cantidad,
            @Fecha AS FechaActualizacion;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        INSERT INTO dbo.SchemaMigrations (
            Numero, Nombre
        )
        VALUES (
            8,
            N'008_CartSaveDetailProcedure'
        );

        PRINT 'Migracion 008 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Carrito_GuardarDetalle', N'P'
        ) IS NULL
            THROW 58011,
                'Migracion registrada sin procedimiento.',
                1;

        PRINT 'Migracion 008 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
