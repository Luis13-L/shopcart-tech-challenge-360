import { z } from "zod";

// ==========================================
// VALIDACIONES DE PAGINACION
// ==========================================

const pageSchema = z.string()
  .regex(
    /^[1-9]\d{0,9}$/,
    "Numero de pagina invalido"
  )
  .transform(Number)
  .refine(
    value =>
      Number.isSafeInteger(value) &&
      value <= 2147483647,
    "Pagina fuera de rango"
  );

const pageSizeSchema = z.string()
  .regex(
    /^[1-9]\d{0,2}$/,
    "Tamano de pagina invalido"
  )
  .transform(Number)
  .refine(
    value => value >= 1 && value <= 100,
    "El tamano debe estar entre 1 y 100"
  );

// ==========================================
// GET /api/admin/users
// ==========================================

export const listAdminUsersSchema = z.object({
  pagina: pageSchema.optional(),

  tamanoPagina: pageSizeSchema.optional(),

  busqueda: z.string()
    .trim()
    .max(
      254,
      "La busqueda supera 254 caracteres"
    )
    .optional(),

  rol: z.enum([
    "Cliente",
    "Operador",
    "Administrador"
  ]).optional(),

  // 1 = activo
  // 0 = inactivo
  activo: z.enum(["0", "1"])
    .transform(value => value === "1")
    .optional()

}).strict().transform(data => ({
  pagina: data.pagina ?? 1,
  tamanoPagina: data.tamanoPagina ?? 10,
  busqueda: data.busqueda || null,
  rol: data.rol ?? null,
  activo: data.activo ?? null
}));

export type ListAdminUsersInput =
  z.infer<typeof listAdminUsersSchema>;
