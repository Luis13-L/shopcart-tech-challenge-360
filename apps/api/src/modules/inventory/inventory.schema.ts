import { z } from "zod";

const positiveInt = z.number()
  .int()
  .positive()
  .max(2147483647);

export const inventoryMovementSchema = z.object({
  idVariante: positiveInt,

  tipoMovimiento: z.enum([
    "ENTRADA",
    "AJUSTE_POSITIVO",
    "AJUSTE_NEGATIVO"
  ]),

  cantidad: positiveInt,

  motivo: z.string()
    .trim()
    .min(3)
    .max(300)
}).strict();

export const inventoryVariantParamsSchema = z.object({
  id: z.string()
    .regex(/^[1-9]\d*$/)
    .transform(Number)
    .refine(
      value =>
        Number.isSafeInteger(value) &&
        value <= 2147483647,
      "Variante invalida"
    )
}).strict();

const pageNumber = z.string()
  .regex(/^[1-9]\d*$/)
  .transform(Number)
  .refine(
    value =>
      Number.isSafeInteger(value) &&
      value <= 2147483647
  );

export const inventoryKardexQuerySchema = z.object({
  pagina: pageNumber.default(1),

  tamanoPagina: pageNumber
    .refine(value => value <= 100)
    .default(20)
}).strict();

export type InventoryMovementInput =
  z.infer<typeof inventoryMovementSchema>;

export type InventoryKardexQuery =
  z.infer<typeof inventoryKardexQuerySchema>;
