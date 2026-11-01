USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- ==========================================
    -- 1. VALIDAR DEPENDENCIAS
    -- ==========================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 37
    )
        THROW 73401,
            'Primero ejecute la migracion 037.',
            1;

    IF OBJECT_ID(
        N'dbo.BitacoraAuditoria', N'U'
    ) IS NULL
        THROW 73402,
            'No existe la tabla de auditoria.',
            1;

    IF OBJECT_ID(
        N'dbo.MovimientosInventario', N'U'
    ) IS NULL
        THROW 73403,
            'No existe la tabla de movimientos.',
            1;

    -- ==========================================
    -- 2. CREAR TRIGGER
    -- ==========================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 38
    )
    BEGIN
        IF OBJECT_ID(
            N'dbo.TR_Inventario_AuditarMovimientos',
            N'TR'
        ) IS NOT NULL
            THROW 73404,
                'El trigger existe sin migracion registrada.',
                1;

        EXEC sys.sp_executesql N'
CREATE TRIGGER dbo.TR_Inventario_AuditarMovimientos
ON dbo.MovimientosInventario
WITH EXECUTE AS OWNER
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

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

        ''INVENTARIO'',

        ''Existencias'',

        CONVERT(VARCHAR(40), i.IDVariante),

        CASE
            WHEN i.TipoMovimiento = ''DEVOLUCION''
                THEN ''DEVOLVER''

            WHEN i.TipoMovimiento IN (
                ''ENTRADA'',
                ''AJUSTE_POSITIVO'',
                ''AJUSTE_NEGATIVO''
            )
                THEN ''AJUSTAR''

            ELSE ''ACTUALIZAR''
        END,

        (
            SELECT
                i.SaldoAnterior AS cantidadFisica
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER
        ),

        (
            SELECT
                i.SaldoPosterior AS cantidadFisica,
                i.TipoMovimiento AS tipoMovimiento,
                i.CantidadFirmada AS cantidadFirmada,
                i.Motivo AS motivo,
                i.IDMovimientoInventario
                    AS idMovimientoInventario
            FOR JSON PATH,
                WITHOUT_ARRAY_WRAPPER,
                INCLUDE_NULL_VALUES
        ),

        i.FechaMovimiento

    FROM inserted AS i;
END;
';

        -- ======================================
        -- 3. REGISTRAR MIGRACION
        -- ======================================

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            38,
            N'038_AuditInventoryMovements'
        );

        PRINT
            'Migracion 038 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.TR_Inventario_AuditarMovimientos',
            N'TR'
        ) IS NULL
            THROW 73405,
                'Migracion registrada pero falta trigger.',
                1;

        PRINT 'Migracion 038 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
