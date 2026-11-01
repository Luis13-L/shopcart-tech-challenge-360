import { z } from "zod";

// ==========================================
// VALIDACION DE FECHAS
// ==========================================

const dateSchema = z.string()
  .regex(
    /^\d{4}-\d{2}-\d{2}$/,
    "La fecha debe tener formato YYYY-MM-DD"
  )
  .refine(value => {
    const date = new Date(
      `${value}T00:00:00.000Z`
    );

    return (
      !Number.isNaN(date.getTime()) &&
      date.toISOString().slice(0, 10) === value &&
      value < "9999-12-31"
    );
  }, "Fecha invalida");

// ==========================================
// VALIDACION DE ENTEROS POSITIVOS
// ==========================================

const positiveInt = z.string()
  .regex(/^[1-9]\d*$/, "Debe ser positivo")
  .transform(Number)
  .refine(
    value =>
      Number.isSafeInteger(value) &&
      value <= 2147483647,
    "Numero fuera de rango"
  );

const dateRangeFields = {
  fechaInicio: dateSchema,
  fechaFin: dateSchema
};

// ==========================================
// RF-08: VENTAS POR PERIODO
// ==========================================

export const salesReportSchema = z.object({
  ...dateRangeFields,

  agrupacion: z.enum([
    "DIA",
    "SEMANA",
    "MES"
  ])
})
.strict()
.refine(
  value => value.fechaInicio <= value.fechaFin,
  {
    path: ["fechaFin"],
    message: "Fecha final anterior a la inicial"
  }
);

// ==========================================
// RF-08: CATEGORIAS Y TOP PRODUCTOS
// ==========================================

export const dateRangeSchema = z.object({
  ...dateRangeFields
})
.strict()
.refine(
  value => value.fechaInicio <= value.fechaFin,
  {
    path: ["fechaFin"],
    message: "Fecha final anterior a la inicial"
  }
);

// ==========================================
// RF-08: LISTADO PAGINADO DE PEDIDOS
// ==========================================

export const ordersReportSchema = z.object({

  estado: z.enum([
    "PAGADO",
    "PREPARANDO",
    "DESPACHADO",
    "ENTREGADO",
    "CANCELADO",
    "DEVUELTO_PARCIAL",
    "DEVUELTO_TOTAL"
  ]).optional(),

  idCliente: positiveInt.optional(),

  fechaInicio: dateSchema.optional(),

  fechaFin: dateSchema.optional(),

  // Valor predeterminado: pagina 1
  // Primero string, luego transformacion a number.
  pagina: z.string()
    .default("1")
    .pipe(positiveInt),

  // Valor predeterminado: 10 registros
  // Limite maximo: 100 por pagina.
  tamanoPagina: z.string()
    .default("10")
    .pipe(
      positiveInt.refine(
        value => value <= 100,
        "Maximo 100 registros por pagina"
      )
    )

})
.strict()
.refine(
  value =>
    !value.fechaInicio ||
    !value.fechaFin ||
    value.fechaInicio <= value.fechaFin,
  {
    path: ["fechaFin"],
    message: "Rango de fechas invalido"
  }
);

// ==========================================
// TIPOS TYPESCRIPT
// ==========================================

export type SalesReportInput =
  z.infer<typeof salesReportSchema>;

export type DateRangeInput =
  z.infer<typeof dateRangeSchema>;

export type OrdersReportInput =
  z.infer<typeof ordersReportSchema>;
