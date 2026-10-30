/*
ShopCart | Verificacion tras prueba de concurrencia
No modifica datos. Una reserva ACTIVA de 8 unidades debe ser del carrito 11
mientras aun no hayan pasado los 15 minutos. La solicitud de B debe fallar
con codigo 65610 en la ventana B.
*/
USE ShopCartDB;
GO
SET NOCOUNT ON;
GO
SELECT r.IDReserva, r.IDCarrito, r.Estado, r.FechaCreacion,
       r.ExpiraEn, d.IDVariante, d.Cantidad
FROM dbo.ReservasInventario AS r
JOIN dbo.DetallesReserva AS d ON d.IDReserva = r.IDReserva
WHERE r.IDCarrito IN (11, 12)
ORDER BY r.IDReserva;

SELECT e.IDVariante,
       e.CantidadFisica,
       COALESCE(SUM(CASE WHEN r.Estado = 'ACTIVA'
                         AND r.ExpiraEn > SYSUTCDATETIME()
                         THEN CONVERT(BIGINT, d.Cantidad)
                         ELSE CONVERT(BIGINT, 0) END), 0) AS CantidadReservadaVigente
FROM dbo.Existencias AS e
LEFT JOIN dbo.DetallesReserva AS d ON d.IDVariante = e.IDVariante
LEFT JOIN dbo.ReservasInventario AS r ON r.IDReserva = d.IDReserva
WHERE e.IDVariante = 4
GROUP BY e.IDVariante, e.CantidadFisica;
GO
