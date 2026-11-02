import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  registerSchema
} from "./auth.register.schema.js";

import {
  registerCustomer
} from "./auth.register.service.js";

const businessErrors: Record<
  number,
  {
    status: number;
    code: string;
    message: string;
  }
> = {
  77010: {
    status: 400,
    code: "INVALID_EMAIL",
    message: "Correo electronico invalido"
  },
  77011: {
    status: 400,
    code: "INVALID_PASSWORD_HASH",
    message: "No se pudo procesar la contrasena"
  },
  77013: {
    status: 409,
    code: "EMAIL_ALREADY_EXISTS",
    message: "El correo ya esta registrado"
  },
  2601: {
    status: 409,
    code: "EMAIL_ALREADY_EXISTS",
    message: "El correo ya esta registrado"
  },
  2627: {
    status: 409,
    code: "EMAIL_ALREADY_EXISTS",
    message: "El correo ya esta registrado"
  }
};

export async function registerController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const validation = registerSchema.safeParse(
    req.body
  );

  if (!validation.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de registro invalidos"
    });
    return;
  }

  try {
    const user = await registerCustomer(
      validation.data
    );

    res.status(201).json({
      message: "Cliente registrado correctamente",
      data: user
    });

  } catch (error) {
    const sqlNumber =
      typeof error === "object" &&
      error !== null &&
      "number" in error &&
      typeof error.number === "number"
        ? error.number
        : undefined;

    const mapped = sqlNumber === undefined
      ? undefined
      : businessErrors[sqlNumber];

    if (mapped) {
      res.status(mapped.status).json({
        code: mapped.code,
        message: mapped.message
      });
      return;
    }

    next(error);
  }
}
