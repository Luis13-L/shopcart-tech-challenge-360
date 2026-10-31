import {
  reserveInventory
} from "./checkout.reservation.repository.js";

export async function createInventoryReservation(
  cartId: string,
  userId: number
) {
  const reservationId = await reserveInventory(
    cartId,
    userId
  );

  return {
    idReserva: reservationId,
    idCarrito: cartId
  };
}
