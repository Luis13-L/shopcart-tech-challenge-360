import { z } from "zod";

const MAX_BIGINT = 9223372036854775807n;

export const orderIdSchema = z.object({
  id: z.string()
    .regex(/^[1-9]\d{0,18}$/, "ID de pedido invalido")
    .refine(
      value => BigInt(value) <= MAX_BIGINT,
      "ID de pedido fuera de rango"
    )
});

export const changeOrderStatusSchema = z.object({
  estadoNuevo: z.enum([
    "PREPARANDO",
    "DESPACHADO",
    "ENTREGADO"
  ]),

  observacion: z.string()
    .trim()
    .min(1)
    .max(300)
    .optional()
}).strict();

export type ChangeOrderStatusInput =
  z.infer<typeof changeOrderStatusSchema>;
