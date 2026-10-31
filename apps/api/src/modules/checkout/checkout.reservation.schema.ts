import { z } from "zod";

export const reserveInventorySchema = z.object({
  idCarrito: z.string()
    .regex(/^[1-9]\d{0,18}$/, "ID de carrito inválido")
    .refine(
      value => BigInt(value) <= 9223372036854775807n,
      "ID de carrito fuera de rango"
    )
}).strict();
