
import { z } from "zod";

export const updateProductSchema = z.object({
  idCategoria: z.number()
    .int()
    .positive()
    .optional(),

  nombre: z.string()
    .trim()
    .min(3)
    .max(200)
    .optional(),

  descripcion: z.string()
    .trim()
    .max(2000)
    .nullable()
    .optional()
}).strict().refine(
  data => Object.keys(data).length > 0,
  { message: "Debe proporcionar al menos un campo" }
);

export type UpdateProductInput =
  z.infer<typeof updateProductSchema>;
