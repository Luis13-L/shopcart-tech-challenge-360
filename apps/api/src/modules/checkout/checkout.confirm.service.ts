import type {
  ConfirmCheckoutInput
} from "./checkout.confirm.schema.js";

import {
  confirmCheckout
} from "./checkout.confirm.repository.js";

export async function confirmCustomerCheckout(
  userId: number,
  input: ConfirmCheckoutInput
) {
  return confirmCheckout(userId, input);
}
