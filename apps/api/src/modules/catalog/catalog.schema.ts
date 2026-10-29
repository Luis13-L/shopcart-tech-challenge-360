
import { z } from "zod";

const priceSchema = z.string()
  .regex(
    /^\d{1,9}(\.\d{1,2})?$/,
    "Ingrese un importe decimal válido"
  )
  .transform(Number);

export const catalogQuerySchema = z.object({
  search: z.string()
    .trim()
    .max(120)
    .optional(),

  categoryId: z.coerce.number()
    .int()
    .positive()
    .optional(),

  minPrice: priceSchema.optional(),
  maxPrice: priceSchema.optional(),

  available: z.enum(["true", "false"])
    .default("false")
    .transform(value => value === "true"),

  sort: z.enum([
    "name_asc",
    "name_desc",
    "price_asc",
    "price_desc"
  ]).default("name_asc"),

  page: z.coerce.number()
    .int()
    .min(1)
    .max(10000)
    .default(1),

  pageSize: z.coerce.number()
    .int()
    .min(1)
    .max(50)
    .default(10)
}).strict().refine(
  data =>
    data.minPrice === undefined ||
    data.maxPrice === undefined ||
    data.minPrice <= data.maxPrice,
  {
    message: "El precio mínimo supera el máximo",
    path: ["maxPrice"]
  }
);

export type CatalogQuery =
  z.infer<typeof catalogQuerySchema>;
