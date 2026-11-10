import { z } from "zod";

// ==========================================
// PAGINACION
// ==========================================

const pageSchema = z.string()
  .regex(
    /^[1-9]\d*$/,
    "Numero de pagina invalido"
  )
  .transform(Number)
  .pipe(
    z.number()
      .int()
      .min(1)
      .max(10000)
  );

const pageSizeSchema = z.string()
  .regex(
    /^[1-9]\d*$/,
    "Tamano de pagina invalido"
  )
  .transform(Number)
  .pipe(
    z.number()
      .int()
      .min(1)
      .max(50)
  );

const categoryIdSchema = z.string()
  .regex(
    /^[1-9]\d*$/,
    "ID de categoria invalido"
  )
  .transform(Number)
  .pipe(
    z.number()
      .int()
      .min(1)
      .max(2147483647)
  );

// ==========================================
// GET /api/admin/products
// ==========================================

export const listAdminProductsSchema =
  z.object({

    pagina: pageSchema.optional(),

    tamanoPagina: pageSizeSchema.optional(),

    busqueda: z.string()
      .trim()
      .max(
        120,
        "La busqueda supera 120 caracteres"
      )
      .optional(),

    activo: z.enum(["0", "1"])
      .transform(value => value === "1")
      .optional(),

    idCategoria: categoryIdSchema.optional()

  })
  .strict()
  .transform(data => ({
    pagina: data.pagina ?? 1,

    tamanoPagina: data.tamanoPagina ?? 10,

    busqueda: data.busqueda || null,

    activo: data.activo ?? null,

    idCategoria: data.idCategoria ?? null
  }));

export type ListAdminProductsInput =
  z.infer<typeof listAdminProductsSchema>;
