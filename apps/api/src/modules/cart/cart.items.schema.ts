
import { z } from "zod";

export const saveCartItemSchema = z.object({
  idVariante: z.number()
    .int()
    .positive()
    .max(2147483647),

  cantidad: z.number()
    .int()
    .positive()
    .max(2147483647)
}).strict();

export type SaveCartItemInput =
  z.infer<typeof saveCartItemSchema>;
