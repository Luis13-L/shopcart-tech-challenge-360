import { z } from "zod";

const MAX_BIGINT = 9223372036854775807n;

const positiveBigIntId = z.string()
  .regex(/^[1-9]\d{0,18}$/, "ID invalido")
  .refine(
    value => BigInt(value) <= MAX_BIGINT,
    "ID fuera de rango"
  );

export const returnOrderParamsSchema = z.object({
  id: positiveBigIntId
});

export const returnOrderBodySchema = z.object({
  idDetallePedido: positiveBigIntId,

  cantidad: z.number()
    .int()
    .positive()
    .max(2147483647),

  motivo: z.string()
    .trim()
    .min(1, "Debe indicar un motivo")
    .max(300),

  claveIdempotencia: z.string()
    .min(16)
    .max(100)
    .regex(
      /^[a-zA-Z0-9_-]+$/,
      "Clave de idempotencia invalida"
    )
}).strict();

export type ReturnOrderInput =
  z.infer<typeof returnOrderBodySchema>;
