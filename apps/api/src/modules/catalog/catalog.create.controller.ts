
import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  createProductSchema
} from "./catalog.create.schema.js";

import {
  createCatalogProduct
} from "./catalog.create.service.js";

export async function createProductController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const validation = createProductSchema.safeParse(
    req.body
  );

  if (!validation.success) {
    res.status(400).json({
      status: 400,
      code: "VALIDATION_ERROR",
      message: "Datos del producto invalidos",
      errors: validation.error.issues.map(
        issue => ({
          field: issue.path.join("."),
          message: issue.message
        })
      )
    });
    return;
  }

  // requireAuth almacena aqui la identidad
  const actor = res.locals.auth as {
    id: number;
    role: string;
  };

  try {
    const product = await createCatalogProduct(
      validation.data,
      actor.id
    );

    res.status(201).json({
      message: "Producto creado correctamente",
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

    // Permisos actuales revocados
    if (sqlNumber === 65107) {
      res.status(403).json({
        status: 403,
        code: "FORBIDDEN",
        message: "Permisos insuficientes"
      });
      return;
    }

    // Categoria inexistente o inactiva
    if (sqlNumber === 65108) {
      res.status(400).json({
        status: 400,
        code: "INVALID_CATEGORY",
        message: "Categoria no disponible"
      });
      return;
    }

    // SKU duplicado
    if (
      sqlNumber === 65109 ||
      sqlNumber === 2601 ||
      sqlNumber === 2627
    ) {
      res.status(409).json({
        status: 409,
        code: "DUPLICATE_SKU",
        message: "El SKU ya existe"
      });
      return;
    }

    next(error);
  }
}
