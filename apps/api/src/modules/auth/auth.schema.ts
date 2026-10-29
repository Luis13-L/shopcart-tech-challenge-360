
import { z } from "zod";

export const loginSchema = z.object({
  correo: z.string()
    .trim()
    .email()
    .max(254)
    .transform(value => value.toLowerCase()),

  password: z.string()
    .min(1)
    .refine(
      value => Buffer.byteLength(value, "utf8") <= 72,
      "La contraseña supera la longitud permitida"
    )
}).strict();

export type LoginInput = z.infer<typeof loginSchema>;
