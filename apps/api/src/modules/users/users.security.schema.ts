import { z } from "zod";

// ==========================================
// PARAMETRO :id
// ==========================================

export const userSecurityParamsSchema = z.object({
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
// PATCH /:id/role
// ==========================================

export const changeUserRoleSchema = z.object({
  rol: z.enum([
    "Cliente",
    "Operador",
    "Administrador"
  ])
}).strict();

// ==========================================
// PATCH /:id/status
// ==========================================

export const changeUserStatusSchema = z.object({
  activo: z.boolean()
}).strict();

export type ChangeUserRoleInput =
  z.infer<typeof changeUserRoleSchema>;

export type ChangeUserStatusInput =
  z.infer<typeof changeUserStatusSchema>;
