import type {
  ChangeOrderStatusInput
} from "./orders.status.schema.js";

import {
  updateOrderStatus
} from "./orders.status.repository.js";

export async function changeOrderStatus(
  orderId: string,
  userId: number,
  input: ChangeOrderStatusInput
) {
  return updateOrderStatus(
    orderId,
    userId,
    input
  );
}
