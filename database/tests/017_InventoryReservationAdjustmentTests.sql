
USE ShopCartDB;
GO

SET NOCOUNT ON;

DECLARE @IDCliente INT;
DECLARE @IDAdministrador INT;
DECLARE @Reserva BIGINT;
DECLARE @Existencia INT;
DECLARE @CantidadCarrito INT;

SELECT @IDCliente = IDUsuario
FROM dbo.Carritos
WHERE IDCarrito = 11
  AND Estado = 'ACTIVO';

SELECT @CantidadCarrito = Cantidad
FROM dbo.DetallesCarrito
WHERE IDCarrito = 11
  AND IDVariante = 4;

SELECT @Existencia = CantidadFisica
FROM dbo.Existencias
WHERE IDVariante = 4;

SELECT TOP (1)
    @IDAdministrador = u.IDUsuario
FROM dbo.Usuarios u
JOIN dbo.Roles r ON r.IDRol = u.IDRol
WHERE r.Nombre = 'Administrador'
  AND u.Activo = 1
ORDER BY u.IDUsuario;

IF @IDCliente IS NULL
   OR @IDAdministrador IS NULL
   OR @CantidadCarrito <> 8
   OR @Existencia <> 10
    THROW 51030,
        'Los datos de prueba no coinciden con el escenario.',
        1;

IF EXISTS (
    SELECT 1
    FROM dbo.ReservasInventario r
    JOIN dbo.DetallesReserva d
      ON d.IDReserva = r.IDReserva
    WHERE d.IDVariante = 4
      AND r.Estado = 'ACTIVA'
      AND r.ExpiraEn > SYSUTCDATETIME()
)
    THROW 51031,
        'Existen reservas vigentes. No ejecute la prueba.',
        1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Reservar 8 de las 10 unidades.
    EXEC dbo.SP_Inventario_ReservarExistencia
        @IDCarrito = 11,
        @IDUsuario = @IDCliente,
        @IDReserva = @Reserva OUTPUT;

    -- Intentar descontar 3 unidades.
    -- Debe fallar: solo quedan 2 disponibles.
    EXEC dbo.SP_Inventario_RegistrarMovimiento
        @IDVariante = 4,
        @IDUsuario = @IDAdministrador,
        @TipoMovimiento = 'AJUSTE_NEGATIVO',
        @Cantidad = 3,
        @Motivo = N'Prueba de proteccion de reservas';

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    SELECT
        'ERROR: el ajuste fue permitido' AS Resultado;

END TRY
BEGIN CATCH
    DECLARE @CodigoError INT = ERROR_NUMBER();
    DECLARE @MensajeError NVARCHAR(4000) =
        ERROR_MESSAGE();

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    SELECT
        @CodigoError AS CodigoError,
        @MensajeError AS MensajeError,
        CASE
            WHEN @CodigoError = 51009 THEN 'OK'
            ELSE 'REVISAR'
        END AS Resultado;
END CATCH;
GO

-- Comprobar que las existencias no cambiaron.
SELECT
    IDVariante,
    CantidadFisica
FROM dbo.Existencias
WHERE IDVariante = 4;
GO
