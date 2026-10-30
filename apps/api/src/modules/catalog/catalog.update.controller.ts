
import type {
  Request,
  Response,
  NextFunction
} from "express";

import { z } from "zod";

import {
  updateProductSchema
} from "./catalog.update.schema.js";

import {
  updateCatalogProduct
} from "./catalog.update.service.js";

const productIdSchema = z.coerce.number()
  .int()
  .positive()
  .max(2147483647);

export async function updateProductController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const idValidation = productIdSchema.safeParse(
    req.params.id
  );

  const bodyValidation = updateProductSchema.safeParse(
    req.body
  );

  if (!idValidation.success || !bodyValidation.success) {
    res.status(400).json({
      status: 400,
      code: "VALIDATION_ERROR",
      message: "Datos de actualizacion invalidos"
    });
    return;
  }

  const actor = res.locals.auth as {
    id: number;
    role: string;
  };

  try {
    const product = await updateCatalogProduct(
      idValidation.data,
      bodyValidation.data,
      actor.id
    );

    res.status(200).json({
      message: "Producto actualizado correctamente",
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

    if (sqlNumber === 65206) {
      res.status(403).json({
        status: 403,
        code: "FORBIDDEN",
        message: "Permisos insuficientes"
      });
      return;
    }

    if (sqlNumber === 65207) {
      res.status(404).json({
        status: 404,
        code: "PRODUCT_NOT_FOUND",
        message: "Producto no encontrado"
      });
      return;
    }

    if (sqlNumber === 65208) {
      res.status(400).json({
        status: 400,
        code: "INVALID_CATEGORY",
        message: "Categoria no disponible"
      });
      return;
    }

    next(error);
  }
}
