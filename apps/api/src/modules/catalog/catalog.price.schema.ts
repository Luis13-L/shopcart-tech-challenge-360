import { z } from "zod";

export const variantPriceParamsSchema = z.object({
  id: z.string()
    .regex(/^[1-9]\d*$/, "ID de variante invalido")
    .transform(Number)
    .refine(
      value =>
        Number.isSafeInteger(value) &&
        value <= 2147483647,
      "ID fuera de rango"
    )
}).strict();

export const updateVariantPriceSchema = z.object({
  precioNuevo: z.string()
    .trim()
    .regex(
      /^(?:0|[1-9]\d{0,8})(?:\.\d{1,2})?$/,
      "Precio invalido; use hasta dos decimales"
    )
    .refine(
      value => Number(value) > 0,
      "El precio debe ser mayor que cero"
    ),

  motivo: z.string()
    .trim()
    .min(3, "Debe indicar un motivo")
    .max(300, "Maximo 300 caracteres")

}).strict();

export type UpdateVariantPriceInput =
  z.infer<typeof updateVariantPriceSchema>;
