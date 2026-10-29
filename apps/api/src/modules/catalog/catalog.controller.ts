import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  catalogQuerySchema
} from "./catalog.schema.js";

import {
  listCatalogProducts
} from "./catalog.service.js";

export async function getCatalogProducts(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const validation =
    catalogQuerySchema.safeParse(req.query);

  if (!validation.success) {
    res.status(400).json({
      status: 400,
      code: "VALIDATION_ERROR",
      message: "Parámetros de consulta inválidos",
      errors: validation.error.issues.map(
        issue => ({
          field: issue.path.join("."),
          message: issue.message
        })
      )
    });
    return;
  }

  try {
    const result = await listCatalogProducts(
      validation.data
    );

    res.status(200).json(result);

  } catch (error) {
    next(error);
  }
}
