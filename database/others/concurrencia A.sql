
USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Variante INT;
DECLARE @Operador INT;

SELECT @Variante = IDVariante
FROM dbo.Variantes
WHERE SKU = N'BOT-500-NEG';

SELECT @Operador = IDUsuario
FROM dbo.Usuarios
WHERE Correo = N'qa-concurrencia@shopcart.invalid';

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = @Variante,
        @IDUsuario = @Operador,
        @TipoMovimiento = 'AJUSTE_NEGATIVO',
        @Cantidad = 1,
        @Motivo = N'QA concurrencia - sesion A';

    -- Mantener bloqueo durante la simulacion
    WAITFOR DELAY '00:00:30';

    COMMIT TRANSACTION;

    SELECT
        'SESION A CONFIRMADA' AS Resultado;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    SELECT ERROR_NUMBER() AS CodigoError,
           ERROR_MESSAGE() AS Mensaje;
END CATCH;
GO
  