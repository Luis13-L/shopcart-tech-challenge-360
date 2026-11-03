import { z } from "zod";

export const createAddressSchema = z.object({
  destinatario: z.string().trim().min(3).max(150),

  telefono: z.string().trim().min(8).max(25),

  departamento: z.string().trim().min(2).max(100),

  municipio: z.string().trim().min(2).max(100),

  direccionLinea1: z.string().trim().min(5).max(250),

  referencia: z.string()
    .trim()
    .max(250)
    .nullish()
    .transform(value => value || null)
}).strict();

export const addressIdParamsSchema = z.object({
  id: z.coerce.number()
    .int()
    .positive()
    .max(2147483647)
});

export type CreateAddressInput =
  z.infer<typeof createAddressSchema>;
