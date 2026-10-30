import type {
  Request,
  Response,
  NextFunction
} from "express";

import { z } from "zod";

import {
  getCartDetails
} from "./cart.read.service.js";

const MAX_BIGINT = 9223372036854775807n;

const cartIdSchema = z.string().refine(
  value =>
    /^[1-9]\d{0,18}$/.test(value) &&
    BigInt(value) <= MAX_BIGINT,
  "ID de carrito invalido"
);

export async function getCartController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const idValidation = cartIdSchema.safeParse(
    req.params.id
  );

  if (!idValidation.success) {
    res.status(400).json({
      status: 400,
      code: "VALIDATION_ERROR",
      message: "ID de carrito invalido"
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
    const cart = await getCartDetails(
      idValidation.data,
      actor.id
    );

    res.status(200).json({
      data: cart
    });

  } catch (error) {
    next(error);
  }
}
