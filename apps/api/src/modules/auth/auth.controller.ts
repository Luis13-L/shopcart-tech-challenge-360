
import type {
  Request,
  Response,
  NextFunction
} from "express";

import { loginSchema } from "./auth.schema.js";
import { login } from "./auth.service.js";

export async function loginController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const validation = loginSchema.safeParse(req.body);

  if (!validation.success) {
    res.status(400).json({
      status: 400,
      code: "VALIDATION_ERROR",
      message: "Datos de inicio de sesión inválidos"
    });
    return;
  }

  try {
    const result = await login(validation.data);

    if (!result) {
      res.status(401).json({
        status: 401,
        code: "INVALID_CREDENTIALS",
        message: "Correo o contraseña incorrectos"
      });
      return;
    }

    res.status(200).json(result);
  } catch (error) {
    next(error);
  }
}
