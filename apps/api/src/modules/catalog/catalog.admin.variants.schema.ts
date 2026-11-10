import { z } from "zod";

const idSchema = z.string()
  .regex(/^[1-9]\d*$/, "ID invalido")
  .transform(Number)
  .pipe(z.number().int().min(1).max(2147483647));

const pageSchema = z.string()
  .regex(/^[1-9]\d*$/, "Pagina invalida")
  .transform(Number)
  .pipe(z.number().int().min(1).max(10000));

const pageSizeSchema = z.string()
  .regex(/^[1-9]\d*$/, "Tamano de pagina invalido")
  .transform(Number)
  .pipe(z.number().int().min(1).max(50));

export const variantIdParamsSchema = z.object({
  id: idSchema
}).strict();

export const listAdminVariantsSchema = z.object({
  idProducto: idSchema,
  pagina: pageSchema.optional(),
  tamanoPagina: pageSizeSchema.optional()
}).strict().transform(data => ({
  idProducto: data.idProducto,
  pagina: data.pagina ?? 1,
  tamanoPagina: data.tamanoPagina ?? 10
}));

const attributeSchema = z.object({
  nombre: z.string().trim().min(1).max(60),
  valor: z.string().trim().min(1).max(100)
}).strict();

export const variantAttributesSchema = z.array(attributeSchema)
  .min(1)
  .max(8)
  .refine(attributes => {
    const names = attributes.map(attribute =>
      attribute.nombre.toLocaleLowerCase("es-GT")
    );
    return new Set(names).size === names.length;
  }, "Los nombres de atributos no pueden repetirse");

const moneySchema = z.string()
  .regex(
    /^(?:0|[1-9]\d{0,8})(?:\.\d{1,2})?$/,
    "Precio invalido"
  )
  .refine(value => Number(value) > 0, "Precio mayor que cero requerido");

export const createAdminVariantSchema = z.object({
  idProducto: z.number().int().positive().max(2147483647),
  sku: z.string().trim().toUpperCase()
    .regex(/^[A-Z0-9._-]{3,64}$/, "SKU invalido"),
  precioActual: moneySchema,
  atributos: variantAttributesSchema
}).strict();

export const changeVariantStatusSchema = z.object({
  activa: z.boolean()
}).strict();

export type ListAdminVariantsInput =
  z.infer<typeof listAdminVariantsSchema>;
export type CreateAdminVariantInput =
  z.infer<typeof createAdminVariantSchema>;
export type ChangeVariantStatusInput =
  z.infer<typeof changeVariantStatusSchema>;
