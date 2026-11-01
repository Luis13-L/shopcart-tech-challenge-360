import { z } from "zod";

const positiveInt = z.string()
  .regex(/^[1-9]\d*$/, "Debe ser positivo")
  .transform(Number)
  .refine(
    value =>
      Number.isSafeInteger(value) &&
      value <= 2147483647,
    "Numero fuera de rango"
  );

const dateSchema = z.string()
  .regex(
    /^\d{4}-\d{2}-\d{2}$/,
    "Formato YYYY-MM-DD requerido"
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

export const auditQuerySchema = z.object({
  modulo: z.enum([
    "CATALOGO",
    "INVENTARIO",
    "CUPONES",
    "PEDIDOS",
    "USUARIOS"
  ]).optional(),

  idUsuarioFiltro: positiveInt.optional(),

  fechaInicio: dateSchema.optional(),

  fechaFin: dateSchema.optional(),

  pagina: z.string()
    .default("1")
    .pipe(positiveInt),

  tamanoPagina: z.string()
    .default("20")
    .pipe(
      positiveInt.refine(
        value => value <= 100,
        "Maximo 100 registros por pagina"
      )
    )

}).strict().refine(
  value =>
    !value.fechaInicio ||
    !value.fechaFin ||
    value.fechaInicio <= value.fechaFin,
  {
    path: ["fechaFin"],
    message: "Rango de fechas invalido"
  }
);

export type AuditQueryInput =
  z.infer<typeof auditQuerySchema>;
