
import {
  findCartDetails
} from "./cart.read.repository.js";

export async function getCartDetails(
  cartId: string,
  userId: number
) {
  return findCartDetails(cartId, userId);
}
