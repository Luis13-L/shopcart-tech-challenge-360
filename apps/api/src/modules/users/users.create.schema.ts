import { z } from "zod";

// ==========================================
// VALIDACION DE CORREO
// ==========================================

const emailSchema = z.string()
  .trim()
  .email("Correo electronico invalido")
  .max(254)
  .transform(value => value.toLowerCase());

// ==========================================
// VALIDACION DE CONTRASENA
// ==========================================

const passwordSchema = z.string()
  .min(
    12,
    "La contrasena debe tener al menos 12 caracteres"
  )
  .refine(
    value => Buffer.byteLength(value, "utf8") <= 72,
    "La contrasena supera los 72 bytes permitidos"
  );

// ==========================================
// ROLES PERMITIDOS
// ==========================================

const roleSchema = z.enum([
  "Cliente",
  "Operador",
  "Administrador"
]);

// ==========================================
// POST /api/admin/users
// ==========================================

export const createAdminUserSchema = z.object({
  correo: emailSchema,
  password: passwordSchema,
  rol: roleSchema
}).strict();

export type CreateAdminUserInput =
  z.infer<typeof createAdminUserSchema>;
