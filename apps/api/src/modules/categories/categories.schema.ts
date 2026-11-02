import { z } from "zod";

const categoryNameSchema = z.string()
  .trim()
  .min(3, "Minimo 3 caracteres")
  .max(120, "Maximo 120 caracteres");

const descriptionSchema = z.string()
  .trim()
  .max(500, "Maximo 500 caracteres")
  .nullable();

// Validar el ID recibido desde la URL.
export const categoryIdParamsSchema = z.object({
  id: z.string()
    .regex(/^[1-9]\d*$/, "ID invalido")
    .transform(Number)
    .refine(
      value =>
        Number.isSafeInteger(value) &&
        value <= 2147483647,
      "ID fuera de rango"
    )
}).strict();

// Crear categoria.
export const createCategorySchema = z.object({
  nombre: categoryNameSchema,
  descripcion: descriptionSchema.optional()
}).strict();

// Actualizar categoria.
// Se requiere al menos un campo.
export const updateCategorySchema = z.object({
  nombre: categoryNameSchema.optional(),
  descripcion: descriptionSchema.optional()
}).strict().refine(
  data => Object.keys(data).length > 0,
  "Debe proporcionar al menos un campo"
);

// Activar o desactivar categoria.
export const categoryStatusSchema = z.object({
  activa: z.boolean()
}).strict();

export type CreateCategoryInput =
  z.infer<typeof createCategorySchema>;

export type UpdateCategoryInput =
  z.infer<typeof updateCategorySchema>;
