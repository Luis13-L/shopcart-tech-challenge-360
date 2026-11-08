import type {
  QuoteCouponInput
} from "./checkout.quote.schema.js";

import {
  quoteCoupon
} from "./checkout.quote.repository.js";

// ==========================================
// SERVICIO DE COTIZACION
// ==========================================

export async function quoteCustomerCoupon(
  userId: number,
  input: QuoteCouponInput
) {
  return quoteCoupon(userId, input);
}
