
import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  getOrCreateUserCart
} from "./cart.service.js";

export async function createCartController(
  _req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const actor = res.locals.auth as
    | { id: number; role: string }
    | undefined;

  if (
    !actor ||
    !Number.isSafeInteger(actor.id) ||
    actor.id <= 0
  ) {
    res.status(401).json({
      status: 401,
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });
    return;
  }

  try {
    const cart = await getOrCreateUserCart(
      actor.id
    );

    res.status(200).json({
      message: "Carrito disponible",
      data: cart
    });

  } catch (error) {
    const sqlNumber =
    typeof error === "object" &&
    error !== null &&
    "number" in error &&
    typeof error.number === "number"
      ? error.number
      : undefined;

  if (sqlNumber === 56003) {
    res.status(403).json({
      status: 403,
      code: "FORBIDDEN",
      message: "Usuario no autorizado para carrito"
    });
    return;
  }
    next(error);
  }
}
