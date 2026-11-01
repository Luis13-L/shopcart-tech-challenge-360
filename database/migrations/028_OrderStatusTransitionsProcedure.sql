USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. Verificar dependencia
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 27
    )
        THROW 67001,
            'Primero ejecute la migracion 027.', 1;

    -- 2. Evitar ejecucion duplicada
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 28
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Pedidos_CambiarEstado',
            N'P'
        ) IS NOT NULL
            THROW 67002,
                'El procedimiento ya existe.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Pedidos_CambiarEstado
    @IDPedido BIGINT,
    @IDUsuario INT,
    @EstadoNuevo VARCHAR(20),
    @Observacion NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IDPedido IS NULL OR @IDPedido <= 0
        THROW 67010, ''Pedido invalido.'', 1;

    IF @IDUsuario IS NULL OR @IDUsuario <= 0
        THROW 67011, ''Usuario invalido.'', 1;

    DECLARE @Rol VARCHAR(50);
    DECLARE @EstadoAnterior VARCHAR(20);
    DECLARE @Fecha DATETIME2(3);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validar operador o administrador activo.
        SELECT @Rol = r.Nombre
        FROM dbo.Usuarios u
        JOIN dbo.Roles r
          ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1;

        IF @Rol IS NULL
           OR @Rol NOT IN (
               ''Operador'',
               ''Administrador''
           )
            THROW 67012,
                ''Usuario sin permisos para gestionar pedidos.'',
                1;

        -- Bloquear el pedido durante la transicion.
        SELECT @EstadoAnterior = Estado
        FROM dbo.Pedidos WITH (UPDLOCK, HOLDLOCK)
        WHERE IDPedido = @IDPedido;

        IF @EstadoAnterior IS NULL
            THROW 67013,
                ''Pedido no encontrado.'', 1;

        -- Solo permitir transiciones validas.
        IF NOT EXISTS (
            SELECT 1
            FROM (
                VALUES
                    (''PAGADO'', ''PREPARANDO''),
                    (''PREPARANDO'', ''DESPACHADO''),
                    (''DESPACHADO'', ''ENTREGADO'')
            ) AS t(Origen, Destino)
            WHERE t.Origen = @EstadoAnterior
              AND t.Destino = @EstadoNuevo
        )
            THROW 67014,
                ''Transicion de estado no permitida.'',
                1;

        SET @Fecha = SYSUTCDATETIME();

        -- Actualizar pedido.
        UPDATE dbo.Pedidos
        SET
            Estado = @EstadoNuevo,
            FechaActualizacion = @Fecha
        WHERE IDPedido = @IDPedido
          AND Estado = @EstadoAnterior;

        IF @@ROWCOUNT <> 1
            THROW 67015,
                ''No se pudo actualizar el estado.'',
                1;

        -- Registrar historial.
        INSERT INTO dbo.HistorialEstadosPedido (
            IDPedido,
            IDUsuario,
            EstadoAnterior,
            EstadoNuevo,
            Observacion,
            FechaCambio
        )
        VALUES (
            @IDPedido,
            @IDUsuario,
            @EstadoAnterior,
            @EstadoNuevo,
            @Observacion,
            @Fecha
        );

        COMMIT TRANSACTION;

        SELECT
            @IDPedido AS IDPedido,
            @EstadoAnterior AS EstadoAnterior,
            @EstadoNuevo AS EstadoNuevo,
            @Fecha AS FechaCambio;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        -- Permitir ejecucion desde la API
        GRANT EXECUTE
        ON OBJECT::dbo.SP_Pedidos_CambiarEstado
        TO [shopcart_api];

        -- Registrar migracion
        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            28,
            N'028_OrderStatusTransitionsProcedure'
        );

        PRINT 'Migracion 028 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.SP_Pedidos_CambiarEstado',
            N'P'
        ) IS NULL
            THROW 67003,
                'Migracion registrada pero falta el SP.',
                1;

        PRINT 'Migracion 028 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
