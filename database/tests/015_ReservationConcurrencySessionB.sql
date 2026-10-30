/*
ShopCart | Prueba de concurrencia - SESION B
Ejecutar en OTRA ventana SSMS mientras A mantiene la transaccion abierta.
Si A reserva 8 de 10 unidades y B solicita 3, B debe devolver error 65610.
*/
USE ShopCartDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
DECLARE @IDClienteB INT;
DECLARE @IDReservaB BIGINT;

SELECT @IDClienteB = IDUsuario
FROM dbo.Carritos
WHERE IDCarrito = 12 AND Estado = 'ACTIVO';

IF @IDClienteB IS NULL
    THROW 65811, 'No existe cliente del carrito 12.', 1;

BEGIN TRY
    EXEC dbo.SP_Inventario_ReservarExistencia
        @IDCarrito = 12,
        @IDUsuario = @IDClienteB,
        @IDReserva = @IDReservaB OUTPUT;

    SELECT @IDReservaB AS IDReservaB,
           'B: reserva creada (inesperado si A mantiene 8 de 10)' AS Resultado;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS CodigoError,
           ERROR_MESSAGE() AS MensajeError;
END CATCH;
GO
