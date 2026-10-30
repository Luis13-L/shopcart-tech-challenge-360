
import type {
  Request,
  Response,
  NextFunction
} from "express";

import { z } from "zod";

import {
  deactivateCatalogProduct
} from "./catalog.deactivate.service.js";

const productIdSchema = z.string()
  .regex(/^[1-9]\d*$/)
  .transform(Number)
  .pipe(
    z.number()
      .int()
      .max(2147483647)
  );

export async function deactivateProductController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const validation = productIdSchema.safeParse(
    req.params.id
  );

  if (!validation.success) {
    res.status(400).json({
      status: 400,
      code: "VALIDATION_ERROR",
      message: "ID de producto invalido"
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
    const product = await deactivateCatalogProduct(
      validation.data,
      actor.id
    );

    res.status(200).json({
      message: "Producto desactivado correctamente",
      data: product
    });

  } catch (error) {
    const sqlNumber =
      typeof error === "object" &&
      error !== null &&
      "number" in error &&
      typeof error.number === "number"
        ? error.number
        : undefined;

    if (sqlNumber === 65303) {
      res.status(403).json({
        status: 403,
        code: "FORBIDDEN",
        message: "Permisos insuficientes"
      });
      return;
    }

    if (sqlNumber === 65304) {
      res.status(404).json({
        status: 404,
        code: "PRODUCT_NOT_FOUND",
        message: "Producto no encontrado"
      });
      return;
    }

    next(error);
  }
}
