
import "dotenv/config";
import { z } from "zod";

const envSchema = z.object({
  // =====================================
  // CONFIGURACION GENERAL
  // =====================================

  NODE_ENV: z.enum([
    "development",
    "test",
    "production"
  ]).default("development"),

  PORT: z.coerce.number()
    .int()
    .min(1)
    .max(65535)
    .default(3000),

  CORS_ORIGIN: z.string()
    .url()
    .default("http://localhost:5173"),

  // =====================================
  // CONFIGURACION SQL SERVER
  // =====================================

  SQL_SERVER: z.string().min(1),

  SQL_PORT: z.coerce.number()
    .int()
    .min(1)
    .max(65535),

  SQL_DATABASE: z.string().min(1),

  SQL_USER: z.string().min(1),

  SQL_PASSWORD: z.string().min(1)
});

export const env = envSchema.parse(process.env);
