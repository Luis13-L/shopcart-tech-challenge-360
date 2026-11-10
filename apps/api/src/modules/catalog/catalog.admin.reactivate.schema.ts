import { z } from "zod";

// ==========================================
// VALIDAR ID DEL PRODUCTO
// ==========================================

export const reactivateProductIdSchema =
  z.string()
    .regex(
      /^[1-9]\d*$/,
      "ID de producto invalido"
    )
    .transform(Number)
    .pipe(
      z.number()
        .int()
        .positive()
        .max(2147483647)
    );
