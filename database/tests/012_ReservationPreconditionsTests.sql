/*
ShopCart | Comprobaciones previas a prueba de concurrencia
No modifica datos. Esperado: carrito 11 tiene 8 y carrito 12 tiene 3
unidades de variante 4; existencia fisica de variante 4 = 10;
no hay reservas vigentes para variante 4.
Si hay reservas vigentes, esperar a que venzan o gestionar su cancelacion
mediante un SP apropiado; no borrar filas manualmente.
*/
USE ShopCartDB;
GO
SET NOCOUNT ON;
GO
SELECT c.IDCarrito, c.IDUsuario, d.IDVariante, d.Cantidad
FROM dbo.Carritos AS c
JOIN dbo.DetallesCarrito AS d ON d.IDCarrito = c.IDCarrito
WHERE c.IDCarrito IN (11, 12)
ORDER BY c.IDCarrito, d.IDVariante;

SELECT IDVariante, CantidadFisica
FROM dbo.Existencias
WHERE IDVariante = 4;

SELECT r.IDReserva, r.IDCarrito, r.Estado, r.ExpiraEn,
       d.IDVariante, d.Cantidad
FROM dbo.ReservasInventario AS r
JOIN dbo.DetallesReserva AS d ON d.IDReserva = r.IDReserva
WHERE d.IDVariante = 4
  AND r.Estado = 'ACTIVA'
  AND r.ExpiraEn > SYSUTCDATETIME()
ORDER BY r.IDReserva;
GO
