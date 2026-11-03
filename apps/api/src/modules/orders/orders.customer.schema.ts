import { z } from "zod";

const MAX_BIGINT = 9223372036854775807n;

const positiveInt = z.string()
  .regex(/^[1-9]\d*$/)
  .transform(Number)
  .refine(
    value =>
      Number.isSafeInteger(value) &&
      value <= 2147483647,
    "Entero fuera de rango"
  );

export const customerOrdersQuerySchema = z.object({
  estado: z.enum([
    "PAGADO",
    "PREPARANDO",
    "DESPACHADO",
    "ENTREGADO",
    "CANCELADO",
    "DEVUELTO_PARCIAL",
    "DEVUELTO_TOTAL"
  ]).optional(),

  pagina: positiveInt.default(1),

  tamanoPagina: positiveInt
    .refine(value => value <= 100, "Maximo 100")
    .default(10)
}).strict();

export const customerOrderIdSchema = z.object({
  id: z.string()
    .regex(/^[1-9]\d{0,18}$/)
    .refine(
      value => BigInt(value) <= MAX_BIGINT,
      "ID fuera de rango"
    )
});

export type CustomerOrdersQuery =
  z.infer<typeof customerOrdersQuerySchema>;
