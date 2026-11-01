import type {
  ReturnOrderInput
} from "./orders.return.schema.js";

import {
  registerOrderReturn
} from "./orders.return.repository.js";

export async function processOrderReturn(
  orderId: string,
  userId: number,
  input: ReturnOrderInput
) {
  return registerOrderReturn(
    orderId,
    userId,
    input
  );
}
