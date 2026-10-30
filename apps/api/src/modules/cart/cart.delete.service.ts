import {
  createOrGetCart
} from "./cart.repository.js";

import {
  deleteCartItem
} from "./cart.delete.repository.js";

import {
  findCartDetails
} from "./cart.read.repository.js";

export async function removeCartItem(
  userId: number,
  variantId: number
) {
  // Reutilizar el carrito activo del cliente
  const cartId = await createOrGetCart(userId);

  // Eliminar la variante
  await deleteCartItem(
    cartId,
    userId,
    variantId
  );

  // Devolver el carrito actualizado
  return findCartDetails(cartId, userId);
}
