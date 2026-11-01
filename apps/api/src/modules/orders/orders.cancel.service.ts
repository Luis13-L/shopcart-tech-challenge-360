import {
  cancelOrder
} from "./orders.cancel.repository.js";

export async function cancelCustomerOrder(
  orderId: string,
  userId: number,
  reason: string
) {
  return cancelOrder(orderId, userId, reason);
}
