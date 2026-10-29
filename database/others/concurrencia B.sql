
USE ShopCartDB;
GO

SET NOCOUNT ON;

DECLARE @Variante INT;
DECLARE @Operador INT;
DECLARE @Inicio DATETIME2(3) = SYSUTCDATETIME();

SELECT @Variante = IDVariante
FROM dbo.Variantes
WHERE SKU = N'BOT-500-NEG';

SELECT @Operador = IDUsuario
FROM dbo.Usuarios
WHERE Correo = N'qa-concurrencia@shopcart.invalid';

BEGIN TRY
    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = @Variante,
        @IDUsuario = @Operador,
        @TipoMovimiento = 'AJUSTE_NEGATIVO',
        @Cantidad = 1,
        @Motivo = N'QA concurrencia - sesion B';

    SELECT 'FALLO: segunda salida permitida'
        AS Resultado;

END TRY
BEGIN CATCH
    SELECT
        CASE
            WHEN ERROR_NUMBER() = 51007
            THEN 'APROBADO'
            ELSE 'REVISAR'
        END AS Resultado,
        ERROR_NUMBER() AS CodigoError,
        ERROR_MESSAGE() AS Mensaje,
        DATEDIFF(
            MILLISECOND,
            @Inicio,
            SYSUTCDATETIME()
        ) AS DuracionMilisegundos;
END CATCH;
GO
  
