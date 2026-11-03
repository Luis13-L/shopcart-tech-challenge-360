import { z } from "zod";

// Validacion de importes monetarios.
// Permitimos un maximo de dos decimales.
const money = z.number()
  .finite()
  .nonnegative()
  .max(1_000_000_000)
  .refine(
    value =>
      Math.abs(
        value * 100 - Math.round(value * 100)
      ) < 0.000001,
    "Use como maximo dos decimales"
  );

// Entero positivo dentro del rango de SQL INT.
const positiveInt = z.number()
  .int()
  .positive()
  .max(2147483647);

// ==========================================
// VALIDAR ID DEL CUPON EN LA URL
// ==========================================

export const couponIdParamsSchema = z.object({
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

// ==========================================
// CREAR Y ACTUALIZAR CUPON
// ==========================================

export const couponBodySchema = z.object({

  codigo: z.string()
    .trim()
    .min(3, "Minimo 3 caracteres")
    .max(50, "Maximo 50 caracteres")
    .regex(
      /^[A-Za-z0-9_-]+$/,
      "Codigo invalido"
    )
    .transform(value => value.toUpperCase()),

  tipoDescuento: z.enum([
    "PORCENTAJE",
    "MONTO_FIJO"
  ]),

  valor: money.refine(
    value => value > 0,
    "El valor debe ser mayor que cero"
  ),

  montoMinimo: money.default(0),

  limiteUsos: positiveInt,

  limitePorCliente: positiveInt.default(1),

  fechaInicio: z.string()
    .datetime({ offset: true }),

  fechaFin: z.string()
    .datetime({ offset: true }),

  activo: z.boolean().default(true)

}).strict().superRefine((value, ctx) => {

  // La fecha final debe ser posterior
  // a la fecha de inicio.
  if (
    new Date(value.fechaFin).getTime() <=
    new Date(value.fechaInicio).getTime()
  ) {
    ctx.addIssue({
      code: "custom",
      path: ["fechaFin"],
      message:
        "fechaFin debe ser posterior a fechaInicio"
    });
  }

  // Un porcentaje no puede superar el 100%.
  if (
    value.tipoDescuento === "PORCENTAJE" &&
    value.valor > 100
  ) {
    ctx.addIssue({
      code: "custom",
      path: ["valor"],
      message:
        "Un porcentaje no puede superar 100"
    });
  }

});

// ==========================================
// ACTIVAR O DESACTIVAR CUPON
// ==========================================

export const couponStatusSchema = z.object({
  activo: z.boolean()
}).strict();

// ==========================================
// FILTRAR LISTADO DE CUPONES
// ==========================================

export const couponListQuerySchema = z.object({
  soloActivos: z.enum([
    "true",
    "false"
  ]).optional()
}).strict();

// ==========================================
// TIPO TYPESCRIPT
// ==========================================

export type CouponInput =
  z.infer<typeof couponBodySchema>;

  // Categoria null = cupón general.
// Un ID positivo = cupón exclusivo de esa categoría.
export const couponCategorySchema = z.object({
  idCategoria: positiveInt.nullable()
}).strict();