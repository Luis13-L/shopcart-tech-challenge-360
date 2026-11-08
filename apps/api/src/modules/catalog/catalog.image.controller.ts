import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  createProductSchema
} from "./catalog.create.schema.js";

import {
  createProductWithImage
} from "./catalog.image.service.js";

import {
  InvalidProductImageError
} from "./catalog.image.storage.js";

export async function createProductWithImageController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actor = res.locals.auth as
    | { id: number; role: string }
    | undefined;

  if (!actor) {
    res.status(401).json({
      code: "UNAUTHORIZED",
      message: "Autenticación requerida"
    });
    return;
  }

  // multipart/form-data transmite los campos
  // de texto como strings.
  const body = {
    ...req.body,
    idCategoria: Number(req.body?.idCategoria)
  };

  const validation = createProductSchema.safeParse(body);

  if (!validation.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos del producto inválidos",
      errors: validation.error.issues.map(issue => ({
        field: issue.path.join("."),
        message: issue.message
      }))
    });
    return;
  }

  if (!req.file) {
    res.status(400).json({
      code: "IMAGE_REQUIRED",
      message: "Selecciona una imagen del producto"
    });
    return;
  }

  try {
    const product = await createProductWithImage(
      actor.id,
      validation.data,
      req.file
    );

    res.status(201).json({
      message: "Producto e imagen registrados",
      data: product
    });

  } catch (error) {
    if (error instanceof InvalidProductImageError) {
      res.status(400).json({
        code: "INVALID_IMAGE",
        message: error.message
      });
      return;
    }

    const number =
      typeof error === "object" &&
      error !== null &&
      "number" in error &&
      typeof error.number === "number"
        ? error.number
        : undefined;

    if (number === 65107 || number === 79503) {
      res.status(403).json({
        code: "FORBIDDEN",
        message: "Permisos insuficientes"
      });
      return;
    }

    if (number === 65108) {
      res.status(400).json({
        code: "INVALID_CATEGORY",
        message: "Categoría inexistente o inactiva"
      });
      return;
    }

    if (
      number === 65109 ||
      number === 2601 ||
      number === 2627
    ) {
      res.status(409).json({
        code: "DUPLICATE_SKU",
        message: "El SKU ya existe"
      });
      return;
    }

    next(error);
  }
}
