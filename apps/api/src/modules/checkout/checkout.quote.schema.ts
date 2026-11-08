import { z } from "zod";

const MAX_BIGINT = 9223372036854775807n;

// ==========================================
// POST /api/checkout/quote
// VALIDACION DE ENTRADA
// ==========================================

export const quoteCouponSchema = z.object({
  idCarrito: z.string()
    .regex(
      /^[1-9]\d{0,18}$/,
      "ID de carrito invalido"
    )
    .refine(
      value => BigInt(value) <= MAX_BIGINT,
      "ID de carrito fuera de rango"
    ),

  codigoCupon: z.string()
    .trim()
    .min(
      3,
      "El codigo debe tener al menos 3 caracteres"
    )
    .max(
      50,
      "El codigo no puede superar 50 caracteres"
    )
    .regex(
      /^[A-Za-z0-9_-]+$/,
      "El codigo contiene caracteres invalidos"
    )
    .transform(value => value.toUpperCase())
}).strict();

export type QuoteCouponInput =
  z.infer<typeof quoteCouponSchema>;
