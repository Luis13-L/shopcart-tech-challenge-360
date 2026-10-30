import type {
  Request,
  Response,
  NextFunction
} from "express";

import { z } from "zod";

import {
  removeCartItem
} from "./cart.delete.service.js";

const variantIdSchema = z.string()
  .regex(/^[1-9]\d*$/)
  .transform(Number)
  .pipe(
    z.number()
      .int()
      .max(2147483647)
  );

export async function deleteCartItemController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const validation = variantIdSchema.safeParse(
    req.params.id
  );

  if (!validation.success) {
    res.status(400).json({
      status: 400,
      code: "VALIDATION_ERROR",
      message: "ID de variante invalido"
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
    const cart = await removeCartItem(
      actor.id,
      validation.data
    );

    res.status(200).json({
      message: "Articulo eliminado del carrito",
      data: cart
    });

  } catch (error) {
    next(error);
  }
}
