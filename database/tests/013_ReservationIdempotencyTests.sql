/*
ShopCart | Prueba: idempotencia de reserva
Ejecutar en SSMS (base ShopCartDB).
Requisitos: migracion 024 aplicada; carrito 11 ACTIVO y con articulos.
Toda reserva creada durante esta prueba se revierte al final.
*/
USE ShopCartDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
DECLARE @IDCliente INT;
DECLARE @Reserva1 BIGINT;
DECLARE @Reserva2 BIGINT;

SELECT @IDCliente = IDUsuario
FROM dbo.Carritos
WHERE IDCarrito = 11
  AND Estado = 'ACTIVO';

IF @IDCliente IS NULL
    THROW 65801, 'No existe carrito 11 activo de cliente.', 1;

IF NOT EXISTS (
    SELECT 1 FROM dbo.DetallesCarrito WHERE IDCarrito = 11
)
    THROW 65802, 'El carrito 11 esta vacio.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC dbo.SP_Inventario_ReservarExistencia
        @IDCarrito = 11,
        @IDUsuario = @IDCliente,
        @IDReserva = @Reserva1 OUTPUT;

    EXEC dbo.SP_Inventario_ReservarExistencia
        @IDCarrito = 11,
        @IDUsuario = @IDCliente,
        @IDReserva = @Reserva2 OUTPUT;

    SELECT
        @Reserva1 AS PrimeraReserva,
        @Reserva2 AS SegundaReserva,
        CASE WHEN @Reserva1 = @Reserva2 THEN 'OK' ELSE 'ERROR' END AS Idempotencia;

    SELECT r.IDReserva, r.IDCarrito, r.Estado,
           r.FechaCreacion, r.ExpiraEn,
           d.IDVariante, d.Cantidad
    FROM dbo.ReservasInventario AS r
    JOIN dbo.DetallesReserva AS d ON d.IDReserva = r.IDReserva
    WHERE r.IDReserva = @Reserva1;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
