
import type {
  SaveCartItemInput
} from "./cart.items.schema.js";

import {
  createOrGetCart
} from "./cart.repository.js";

import {
  saveCartItem
} from "./cart.items.repository.js";

import {
  findCartDetails
} from "./cart.read.repository.js";

export async function addOrUpdateCartItem(
  userId: number,
  input: SaveCartItemInput
) {
  // Obtener el carrito activo del cliente.
  // No confiamos en un ID enviado por el frontend.
  const cartId = await createOrGetCart(userId);

  // Guardar la cantidad absoluta.
  await saveCartItem(
    cartId,
    userId,
    input.idVariante,
    input.cantidad
  );

  // Devolver el carrito con sus totales actualizados.
  return findCartDetails(cartId, userId);
}
