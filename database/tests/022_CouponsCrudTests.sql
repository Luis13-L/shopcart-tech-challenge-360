USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- TEST 022: CRUD SQL de cupones. Todos los datos se revierten.
DECLARE @IDAdmin INT;
DECLARE @IDCupon INT;
DECLARE @Inicio DATETIME2(3) = DATEADD(DAY, -1, SYSUTCDATETIME());
DECLARE @Fin DATETIME2(3) = DATEADD(DAY, 7, SYSUTCDATETIME());
DECLARE @Codigo VARCHAR(50) = CONCAT(
    'CRUDTEST_', LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 12)
);

SELECT TOP (1) @IDAdmin = u.IDUsuario
FROM dbo.Usuarios u
JOIN dbo.Roles r ON r.IDRol = u.IDRol
WHERE u.Activo = 1 AND r.Nombre = N'Administrador'
ORDER BY u.IDUsuario;

IF @IDAdmin IS NULL
    THROW 71101, 'Falta un Administrador activo para la prueba.', 1;

IF NOT EXISTS (SELECT 1 FROM dbo.SchemaMigrations WHERE Numero = 33)
    THROW 71102, 'Primero ejecutar la migracion 033.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Crear un cupon de prueba. No se modifica BIENVENIDA10.
    EXEC dbo.SP_Cupones_Crear
        @IDUsuario = @IDAdmin,
        @Codigo = @Codigo,
        @TipoDescuento = 'PORCENTAJE',
        @Valor = 15.00,
        @LimiteUsos = 10,
        @FechaInicio = @Inicio,
        @FechaFin = @Fin,
        @MontoMinimo = 100.00,
        @LimitePorCliente = 1,
        @Activo = 1;

    SELECT @IDCupon = IDCupon
    FROM dbo.Cupones
    WHERE Codigo = @Codigo;

    IF @IDCupon IS NULL
        THROW 71103, 'No se creo el cupon.', 1;

    PRINT 'OK: Crear cupon.';

    -- Consultar por identificador.
    EXEC dbo.SP_Cupones_Obtener
        @IDUsuario = @IDAdmin,
        @IDCupon = @IDCupon;

    -- Actualizar el porcentaje, limites y condiciones ANTES de tener usos.
    EXEC dbo.SP_Cupones_Actualizar
        @IDUsuario = @IDAdmin,
        @IDCupon = @IDCupon,
        @Codigo = @Codigo,
        @TipoDescuento = 'PORCENTAJE',
        @Valor = 20.00,
        @LimiteUsos = 2,
        @FechaInicio = @Inicio,
        @FechaFin = @Fin,
        @MontoMinimo = 150.00,
        @LimitePorCliente = 1,
        @Activo = 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.Cupones
        WHERE IDCupon = @IDCupon
          AND Valor = 20.00 AND LimiteUsos = 2
          AND MontoMinimo = 150.00
    ) THROW 71104, 'Fallo la actualizacion.', 1;

    PRINT 'OK: Actualizar cupon.';

    -- Desactivacion logica.
    EXEC dbo.SP_Cupones_CambiarEstado
        @IDUsuario = @IDAdmin,
        @IDCupon = @IDCupon,
        @Activo = 0;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.Cupones
        WHERE IDCupon = @IDCupon AND Activo = 0
    ) THROW 71105, 'Fallo la desactivacion.', 1;

    PRINT 'OK: Desactivar cupon.';

    -- Reactivacion.
    EXEC dbo.SP_Cupones_CambiarEstado
        @IDUsuario = @IDAdmin,
        @IDCupon = @IDCupon,
        @Activo = 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.Cupones
        WHERE IDCupon = @IDCupon AND Activo = 1
    ) THROW 71106, 'Fallo la reactivacion.', 1;

    PRINT 'OK: Reactivar cupon.';

    -- Listados administrativos.
    EXEC dbo.SP_Cupones_Listar
        @IDUsuario = @IDAdmin,
        @SoloActivos = 1;

    EXEC dbo.SP_Cupones_ListarUsos
        @IDUsuario = @IDAdmin,
        @IDCupon = @IDCupon;

    PRINT 'OK: Consultar lista de cupones e historial de usos.';

    -- No conservar datos ficticios.
    ROLLBACK TRANSACTION;

    IF EXISTS (SELECT 1 FROM dbo.Cupones WHERE Codigo = @Codigo)
        THROW 71107, 'El ROLLBACK no elimino el cupon temporal.', 1;

    SELECT
        'OK: CRUD de cupones y ROLLBACK correcto' AS Resultado,
        @Codigo AS CodigoTemporal,
        @IDAdmin AS IDAdministrador;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
