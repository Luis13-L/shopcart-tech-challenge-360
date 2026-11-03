import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  inventoryMovementSchema,
  inventoryVariantParamsSchema,
  inventoryKardexQuerySchema
} from "./inventory.schema.js";

import {
  inventoryService
} from "./inventory.service.js";

function actorId(res: Response): number | null {
  const auth = res.locals.auth as
    | { id: number; role: string }
    | undefined;

  return auth?.id ?? null;
}

function handleError(
  error: unknown,
  res: Response,
  next: NextFunction
): void {
  const number =
    typeof error === "object" &&
    error !== null &&
    "number" in error &&
    typeof error.number === "number"
      ? error.number
      : undefined;

  if (number === 51005 || number === 78701) {
    res.status(403).json({
      code: "FORBIDDEN",
      message: "Usuario sin permisos de inventario"
    });
    return;
  }

  if (number === 51006 || number === 78704) {
    res.status(404).json({
      code: "INVENTORY_NOT_FOUND",
      message: "Variante sin inventario"
    });
    return;
  }

  if (
    number === 51007 ||
    number === 51008 ||
    number === 51009
  ) {
    res.status(409).json({
      code: "INVENTORY_CONFLICT",
      message: "El movimiento no puede aplicarse"
    });
    return;
  }

  if (
    (number != null && number >= 51001 && number <= 51004) ||
    number === 78702 ||
    number === 78703
  ) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Parametros de inventario invalidos"
    });
    return;
  }

  next(error);
}

// POST /api/inventory/movements
export async function registerMovementController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const id = actorId(res);

  if (id === null) {
    res.status(401).json({
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });
    return;
  }

  const parsed = inventoryMovementSchema.safeParse(
    req.body
  );

  if (!parsed.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Movimiento invalido"
    });
    return;
  }

  try {
    const data = await inventoryService.register(
      id, parsed.data
    );

    res.status(201).json({ data });
  } catch (error) {
    handleError(error, res, next);
  }
}

// GET /api/inventory/variants/:id
export async function getStockController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const id = actorId(res);
  const params = inventoryVariantParamsSchema.safeParse(
    req.params
  );

  if (id === null) {
    res.status(401).json({
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });
    return;
  }

  if (!params.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "ID de variante invalido"
    });
    return;
  }

  try {
    const data = await inventoryService.stock(
      id, params.data.id
    );

    if (!data) {
      res.status(404).json({
        code: "INVENTORY_NOT_FOUND",
        message: "Variante sin inventario"
      });
      return;
    }

    res.status(200).json({ data });
  } catch (error) {
    handleError(error, res, next);
  }
}

// GET /api/inventory/variants/:id/movements
export async function getKardexController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const id = actorId(res);
  const params = inventoryVariantParamsSchema.safeParse(
    req.params
  );
  const query = inventoryKardexQuerySchema.safeParse(
    req.query
  );

  if (id === null) {
    res.status(401).json({
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });
    return;
  }

  if (!params.success || !query.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Parametros de kardex invalidos"
    });
    return;
  }

  try {
    const data = await inventoryService.kardex(
      id, params.data.id, query.data
    );

    res.status(200).json({ data });
  } catch (error) {
    handleError(error, res, next);
  }
}
