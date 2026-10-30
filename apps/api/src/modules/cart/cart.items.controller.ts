
import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  saveCartItemSchema
} from "./cart.items.schema.js";

import {
  addOrUpdateCartItem
} from "./cart.items.service.js";

export async function saveCartItemController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const validation = saveCartItemSchema.safeParse(
    req.body
  );

  if (!validation.success) {
    res.status(400).json({
      status: 400,
      code: "VALIDATION_ERROR",
      message: "Datos del carrito invalidos",
      errors: validation.error.issues.map(
        issue => ({
          field: issue.path.join("."),
          message: issue.message
        })
      )
    });
    return;
  }

  const actor = res.locals.auth as
    | { id: number; role: string }
    | undefined;

  if (!actor) {
    res.status(401).json({
      status: 401,
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });
    return;
  }

  try {
    const cart = await addOrUpdateCartItem(
      actor.id,
      validation.data
    );

    res.status(200).json({
      message: "Carrito actualizado correctamente",
      data: cart
    });

  } catch (error) {
    next(error);
  }
}
