/*
ShopCart | Prueba de concurrencia - SESION A
1) Primero verificar condiciones con 00_Verificar_Precondiciones.sql.
2) Ejecutar esta sesion y, mientras espera 25 segundos, ejecutar SESION B.
3) La reserva de A queda persistida por 15 minutos (no descuenta stock fisico).
*/
USE ShopCartDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
DECLARE @IDClienteA INT;
DECLARE @IDReservaA BIGINT;

SELECT @IDClienteA = IDUsuario
FROM dbo.Carritos
WHERE IDCarrito = 11 AND Estado = 'ACTIVO';

IF @IDClienteA IS NULL
    THROW 65810, 'No existe cliente del carrito 11.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC dbo.SP_Inventario_ReservarExistencia
        @IDCarrito = 11,
        @IDUsuario = @IDClienteA,
        @IDReserva = @IDReservaA OUTPUT;

    SELECT @IDReservaA AS IDReservaA,
           'A: reserva creada; comienza espera de 25 segundos' AS Resultado;

    WAITFOR DELAY '00:00:25';

    COMMIT TRANSACTION;
    SELECT 'A: reserva confirmada; COMMIT' AS Resultado;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    SELECT ERROR_NUMBER() AS CodigoError, ERROR_MESSAGE() AS MensajeError;
END CATCH;
GO
