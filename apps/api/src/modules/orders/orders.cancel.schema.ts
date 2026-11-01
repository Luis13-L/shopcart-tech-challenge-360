import { z } from "zod";

const MAX_BIGINT = 9223372036854775807n;

export const cancelOrderParamsSchema = z.object({
  id: z.string()
    .regex(/^[1-9]\d{0,18}$/, "ID de pedido invalido")
    .refine(
      value => BigInt(value) <= MAX_BIGINT,
      "ID de pedido fuera de rango"
    )
});

export const cancelOrderBodySchema = z.object({
  motivo: z.string()
    .trim()
    .min(1, "Debe indicar un motivo")
    .max(200, "Maximo 200 caracteres")
}).strict();

export type CancelOrderInput =
  z.infer<typeof cancelOrderBodySchema>;
