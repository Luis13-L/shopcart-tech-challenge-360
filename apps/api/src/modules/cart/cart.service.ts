
import {
  createOrGetCart
} from "./cart.repository.js";

export async function getOrCreateUserCart(
  userId: number
) {
  const idCarrito = await createOrGetCart(userId);

  return {
    idCarrito
  };
}
