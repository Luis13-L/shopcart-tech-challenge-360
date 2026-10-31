import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  reserveInventorySchema
} from "./checkout.reservation.schema.js";

import {
  createInventoryReservation
} from "./checkout.reservation.service.js";

export async function reserveInventoryController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const validation = reserveInventorySchema.safeParse(req.body);

  if (!validation.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de reserva inválidos"
    });
    return;
  }

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

  try {
    const data = await createInventoryReservation(
      validation.data.idCarrito,
      actor.id
    );

    res.status(200).json({
      message: "Reserva de inventario disponible",
      data
    });

  } catch (error) {
    const sqlNumber =
      typeof error === "object" &&
      error !== null &&
      "number" in error &&
      typeof error.number === "number"
        ? error.number
        : undefined;

    const knownErrors: Record<
      number,
      { status: number; code: string; message: string }
    > = {
      65602: {
        status: 400,
        code: "INVALID_CART",
        message: "Carrito inválido"
      },
      65603: {
        status: 400,
        code: "INVALID_USER",
        message: "Usuario inválido"
      },
      65604: {
        status: 403,
        code: "FORBIDDEN",
        message: "Cliente no autorizado"
      },
      65605: {
        status: 404,
        code: "CART_NOT_FOUND",
        message: "Carrito no disponible"
      },
      65606: {
        status: 409,
        code: "EMPTY_CART",
        message: "El carrito está vacío"
      },
      65607: {
        status: 409,
        code: "PRODUCT_UNAVAILABLE",
        message: "El carrito contiene productos no disponibles"
      },
      65608: {
        status: 409,
        code: "CART_CHANGED",
        message: "El carrito cambió durante la reserva vigente"
      },
      65609: {
        status: 409,
        code: "INVENTORY_NOT_FOUND",
        message: "Una variante no tiene inventario"
      },
      65610: {
        status: 409,
        code: "INSUFFICIENT_STOCK",
        message: "Existencias disponibles insuficientes"
      }
    };

    const mapped = sqlNumber === undefined
      ? undefined
      : knownErrors[sqlNumber];

    if (mapped) {
      res.status(mapped.status).json({
        code: mapped.code,
        message: mapped.message
      });
      return;
    }

    next(error);
  }
}
