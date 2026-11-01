import { z } from "zod";

const MAX_BIGINT = 9223372036854775807n;

export const confirmCheckoutSchema = z.object({
  idReserva: z.string()
    .regex(/^[1-9]\d{0,18}$/)
    .refine(
      value => BigInt(value) <= MAX_BIGINT,
      "IDReserva fuera de rango"
    ),

  idDireccion: z.number()
    .int()
    .positive()
    .max(2147483647),

  claveIdempotencia: z.string()
    .regex(
      /^[a-zA-Z0-9_-]{16,100}$/,
      "Clave de idempotencia invalida"
    ),

  totalEsperado: z.string()
    .regex(
      /^(0|[1-9]\d{0,16})\.\d{2}$/,
      "El total debe tener dos decimales"
    ),

  codigoCupon: z.string()
  .trim()
  .min(3, "El codigo debe tener al menos 3 caracteres")
  .max(50, "El codigo no puede superar 50 caracteres")
  .regex(
    /^[A-Za-z0-9_-]+$/,
    "El codigo solo admite letras, numeros, guiones y guion bajo"
  )
  .transform(value => value.toUpperCase())
  .optional(), 
}).strict();

export type ConfirmCheckoutInput =
  z.infer<typeof confirmCheckoutSchema>;
