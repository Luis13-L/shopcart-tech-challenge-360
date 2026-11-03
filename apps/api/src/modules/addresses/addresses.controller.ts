import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  createAddressSchema,
  addressIdParamsSchema
} from "./addresses.schema.js";

import {
  addressesService
} from "./addresses.service.js";

function getActorId(
  res: Response
): number | undefined {
  const actor = res.locals.auth as
    | { id: number; role: string }
    | undefined;

  return actor?.id;
}

function handleError(
  error: unknown,
  res: Response,
  next: NextFunction
): void {
  const sqlNumber =
    typeof error === "object" &&
    error !== null &&
    "number" in error &&
    typeof error.number === "number"
      ? error.number
      : undefined;

  if (
    sqlNumber === 78210 ||
    sqlNumber === 78211 ||
    sqlNumber === 78213
  ) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de direccion invalidos"
    });
    return;
  }

  if (sqlNumber === 78212) {
    res.status(403).json({
      code: "FORBIDDEN",
      message: "Cliente no autorizado"
    });
    return;
  }

  next(error);
}

// ======================================
// POST /api/addresses
// ======================================

export async function createAddressController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actorId = getActorId(res);

  if (!actorId) {
    res.status(401).json({
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });
    return;
  }

  const parsed = createAddressSchema.safeParse(
    req.body
  );

  if (!parsed.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de direccion invalidos",
      errors: parsed.error.issues.map(issue => ({
        field: issue.path.join("."),
        message: issue.message
      }))
    });
    return;
  }

  try {
    const data = await addressesService.create(
      actorId,
      parsed.data
    );

    res.status(201).json({ data });

  } catch (error) {
    handleError(error, res, next);
  }
}

// ======================================
// GET /api/addresses
// ======================================

export async function listAddressesController(
  _req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actorId = getActorId(res);

  if (!actorId) {
    res.status(401).json({
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });
    return;
  }

  try {
    const data = await addressesService.list(
      actorId
    );

    res.status(200).json({ data });

  } catch (error) {
    handleError(error, res, next);
  }
}

// ======================================
// GET /api/addresses/:id
// ======================================

export async function getAddressController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actorId = getActorId(res);

  if (!actorId) {
    res.status(401).json({
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });
    return;
  }

  const params = addressIdParamsSchema.safeParse(
    req.params
  );

  if (!params.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "ID de direccion invalido"
    });
    return;
  }

  try {
    const data = await addressesService.get(
      actorId,
      params.data.id
    );

    if (!data) {
      res.status(404).json({
        code: "ADDRESS_NOT_FOUND",
        message: "Direccion no encontrada"
      });
      return;
    }

    res.status(200).json({ data });

  } catch (error) {
    handleError(error, res, next);
  }
}
