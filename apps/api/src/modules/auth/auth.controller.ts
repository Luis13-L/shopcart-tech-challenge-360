import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  loginSchema
} from "./auth.schema.js";

import {
  login
} from "./auth.service.js";

import {
  setRefreshCookie
} from "./auth.refresh.controller.js";

export async function loginController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const validation = loginSchema.safeParse(
    req.body
  );

  if (!validation.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de inicio de sesion invalidos"
    });
    return;
  }

  try {
    const result = await login(
      validation.data
    );

    if (!result) {
      res.status(401).json({
        code: "INVALID_CREDENTIALS",
        message: "Correo o contrasena incorrectos"
      });
      return;
    }

    setRefreshCookie(
      res,
      result.refreshToken
    );

    const { refreshToken: _hidden, ...data } =
      result;

    res.status(200).json(data);

  } catch (error) {
    next(error);
  }
}
