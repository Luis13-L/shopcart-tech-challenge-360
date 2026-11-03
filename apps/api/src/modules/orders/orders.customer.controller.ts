import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  customerOrdersQuerySchema,
  customerOrderIdSchema
} from "./orders.customer.schema.js";

import {
  customerOrdersService
} from "./orders.customer.service.js";

function getActorId(res: Response): number | null {
  const actor = res.locals.auth as
    | { id: number; role: string }
    | undefined;

  return actor?.id ?? null;
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

  if (number === 78510) {
    res.status(403).json({
      code: "FORBIDDEN",
      message: "Cliente no autorizado"
    });
    return;
  }

  if (
    number === 78511 ||
    number === 78512 ||
    number === 78513
  ) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Parametros invalidos"
    });
    return;
  }

  if (number === 78521) {
    res.status(404).json({
      code: "ORDER_NOT_FOUND",
      message: "Pedido no encontrado"
    });
    return;
  }

  next(error);
}

// GET /api/orders/my
export async function listMyOrdersController(
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

  const parsed = customerOrdersQuerySchema.safeParse(
    req.query
  );

  if (!parsed.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Filtros invalidos"
    });
    return;
  }

  try {
    const data = await customerOrdersService.list(
      actorId,
      parsed.data
    );

    res.status(200).json({ data });

  } catch (error) {
    handleError(error, res, next);
  }
}

// GET /api/orders/my/:id
export async function getMyOrderController(
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

  const parsed = customerOrderIdSchema.safeParse(
    req.params
  );

  if (!parsed.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "ID de pedido invalido"
    });
    return;
  }

  try {
    const data = await customerOrdersService.get(
      actorId,
      parsed.data.id
    );

    res.status(200).json({ data });

  } catch (error) {
    handleError(error, res, next);
  }
}
