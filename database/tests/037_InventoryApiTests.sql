USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 48
)
    THROW 78800,
        'Ejecute primero la migracion 048.', 1;
GO

DECLARE @Operador INT = (
    SELECT IDUsuario
    FROM dbo.Usuarios
    WHERE Correo = N'operador.demo@shopcart.test'
      AND Activo = 1
);

DECLARE @Variante INT = (
    SELECT TOP (1) IDVariante
    FROM dbo.Existencias
    ORDER BY IDVariante
);

DECLARE @SaldoInicial INT;
DECLARE @SaldoFinal INT;

IF @Operador IS NULL OR @Variante IS NULL
    THROW 78801,
        'Falta el Operador demo o una variante.', 1;

-- Consultar inventario.
EXEC dbo.SP_Inventario_ConsultarExistencia
    @IDUsuario = @Operador,
    @IDVariante = @Variante;

-- Consultar kardex.
EXEC dbo.SP_Inventario_ListarKardex
    @IDUsuario = @Operador,
    @IDVariante = @Variante,
    @Pagina = 1,
    @TamanoPagina = 10;

BEGIN TRY
    BEGIN TRANSACTION;

    SELECT @SaldoInicial = CantidadFisica
    FROM dbo.Existencias
    WHERE IDVariante = @Variante;

    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = @Variante,
        @IDUsuario = @Operador,
        @TipoMovimiento = 'ENTRADA',
        @Cantidad = 1,
        @Motivo = N'Prueba RF-03 con rollback';

    SELECT @SaldoFinal = CantidadFisica
    FROM dbo.Existencias
    WHERE IDVariante = @Variante;

    IF @SaldoFinal <> @SaldoInicial + 1
        THROW 78802,
            'El movimiento no actualizo existencias.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.MovimientosInventario
        WHERE IDVariante = @Variante
          AND IDUsuario = @Operador
          AND Motivo = N'Prueba RF-03 con rollback'
    )
        THROW 78803,
            'No se registro el kardex.', 1;

    ROLLBACK TRANSACTION;

    IF (
        SELECT CantidadFisica
        FROM dbo.Existencias
        WHERE IDVariante = @Variante
    ) <> @SaldoInicial
        THROW 78804,
            'El rollback no restauro la existencia.', 1;

    PRINT 'OK: movimiento y kardex verificados.';
    PRINT 'OK: rollback completado.';

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
