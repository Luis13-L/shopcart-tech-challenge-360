
import { z } from "zod";

export const createProductSchema = z.object({
  idCategoria: z.number()
    .int()
    .positive(),

  nombre: z.string()
    .trim()
    .min(3)
    .max(200),

  descripcion: z.string()
    .trim()
    .max(2000)
    .optional(),

  sku: z.string()
    .trim()
    .min(3)
    .max(64)
    .regex(/^[A-Za-z0-9._-]+$/)
    .transform(value => value.toUpperCase()),

  precioActual: z.string()
    .regex(
      /^(?:0|[1-9]\d{0,8})(?:\.\d{1,2})?$/,
      "El precio debe tener hasta dos decimales"
    )
    .refine(
      value => Number(value) > 0,
      "El precio debe ser mayor que cero"
    )
}).strict();

export type CreateProductInput =
  z.infer<typeof createProductSchema>;
