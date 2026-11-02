import { z } from "zod";

export const registerSchema = z.object({
  correo: z.string()
    .trim()
    .email("Correo electrónico inválido")
    .max(254)
    .transform(value => value.toLowerCase()),

  password: z.string()
    .min(12, "La contraseña debe tener al menos 12 caracteres")
    .refine(
      value => Buffer.byteLength(value, "utf8") <= 72,
      "La contraseña supera los 72 bytes permitidos"
    )
}).strict();

export type RegisterInput =
  z.infer<typeof registerSchema>;
