USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ==========================================
-- MIGRACION 037
-- AUDITORIA AUTOMATICA DE ESTADOS DE PEDIDO
--
-- Captura:
-- CREAR
-- CAMBIAR_ESTADO
-- CANCELAR
-- DEVOLVER
--
-- No requiere modificar los SPs existentes.
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 36
    )
        THROW 73201,
            'Primero ejecute la migracion 036.',
            1;

    IF OBJECT_ID(
        N'dbo.BitacoraAuditoria',
        N'U'
    ) IS NULL
        THROW 73202,
            'No existe la tabla de auditoria.',
            1;

    IF OBJECT_ID(
        N'dbo.HistorialEstadosPedido',
        N'U'
    ) IS NULL
        THROW 73203,
            'No existe el historial de pedidos.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 37
    )
    BEGIN

        IF OBJECT_ID(
            N'dbo.TR_Pedidos_AuditarEstados',
            N'TR'
        ) IS NOT NULL
            THROW 73204,
                'Existe el trigger sin migracion registrada.',
                1;

        EXEC sys.sp_executesql N'
CREATE TRIGGER dbo.TR_Pedidos_AuditarEstados
ON dbo.HistorialEstadosPedido
WITH EXECUTE AS OWNER
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Insertar en conjunto: funciona incluso
    -- cuando una sentencia agrega varios estados.

    INSERT INTO dbo.BitacoraAuditoria (
        IDUsuario,
        Modulo,
        Entidad,
        IDEntidad,
        Accion,
        ValoresAnteriores,
        ValoresNuevos,
        FechaRegistro
    )
    SELECT
        i.IDUsuario,
        ''PEDIDOS'',
        ''Pedidos'',
        CONVERT(VARCHAR(40), i.IDPedido),

        CASE
            WHEN i.EstadoAnterior IS NULL
                THEN ''CREAR''

            WHEN i.EstadoNuevo = ''CANCELADO''
                THEN ''CANCELAR''

            WHEN i.EstadoNuevo IN (
                ''DEVUELTO_PARCIAL'',
                ''DEVUELTO_TOTAL''
            )
                THEN ''DEVOLVER''

            ELSE ''CAMBIAR_ESTADO''
        END,

        CASE
            WHEN i.EstadoAnterior IS NULL
                THEN NULL
            ELSE (
                SELECT
                    i.EstadoAnterior AS estado
                FOR JSON PATH,
                    WITHOUT_ARRAY_WRAPPER
            )
        END,

        (
            SELECT
                i.EstadoNuevo AS estado,
                i.Observacion AS observacion
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER,
                INCLUDE_NULL_VALUES
        ),

        i.FechaCambio

    FROM inserted AS i;
END;
';

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            37,
            N'037_AuditOrderStatesTrigger'
        );

        PRINT
            'Migracion 037 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.TR_Pedidos_AuditarEstados',
            N'TR'
        ) IS NULL
            THROW 73205,
                'Migracion registrada pero falta trigger.',
                1;

        PRINT 'Migracion 037 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
