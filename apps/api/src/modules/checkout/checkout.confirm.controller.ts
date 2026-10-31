import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  confirmCheckoutSchema
} from "./checkout.confirm.schema.js";

import {
  confirmCustomerCheckout
} from "./checkout.confirm.service.js";

const businessErrors: Record<
  number,
  {
    status: number;
    code: string;
    message: string;
  }
> = {
  66010: {
    status: 400,
    code: "INVALID_USER",
    message: "Usuario invalido"
  },
  66011: {
    status: 400,
    code: "INVALID_RESERVATION",
    message: "Reserva invalida"
  },
  66012: {
    status: 400,
    code: "INVALID_ADDRESS",
    message: "Direccion invalida"
  },
  66013: {
    status: 400,
    code: "INVALID_IDEMPOTENCY_KEY",
    message: "Clave de idempotencia invalida"
  },
  66014: {
    status: 400,
    code: "INVALID_TOTAL",
    message: "Total esperado invalido"
  },
  66015: {
    status: 409,
    code: "IDEMPOTENCY_CONFLICT",
    message: "La clave ya fue usada con otros datos"
  },
  66016: {
    status: 403,
    code: "FORBIDDEN",
    message: "Cliente no autorizado"
  },
  66017: {
    status: 404,
    code: "RESERVATION_NOT_FOUND",
    message: "Reserva no encontrada"
  },
  66018: {
    status: 409,
    code: "CART_UNAVAILABLE",
    message: "Carrito no disponible"
  },
  66019: {
    status: 409,
    code: "EMPTY_CART",
    message: "El carrito esta vacio"
  },
  66020: {
    status: 409,
    code: "RESERVATION_EXPIRED",
    message: "Reserva no vigente"
  },
  66021: {
    status: 409,
    code: "CART_CHANGED",
    message: "El carrito cambio despues de reservar"
  },
  66022: {
    status: 404,
    code: "ADDRESS_NOT_FOUND",
    message: "Direccion no disponible"
  },
  66023: {
    status: 409,
    code: "PRODUCT_UNAVAILABLE",
    message: "Hay productos no disponibles"
  },
  66024: {
    status: 409,
    code: "TOTAL_CHANGED",
    message: "El total cambio; confirma nuevamente"
  },
  66025: {
    status: 409,
    code: "INSUFFICIENT_STOCK",
    message: "Existencia fisica insuficiente"
  },
  66026: {
    status: 409,
    code: "STOCK_RESERVED",
    message: "La compra afectaria otras reservas"
  },
  66027: {
    status: 409,
    code: "RESERVATION_CONFIRMATION_FAILED",
    message: "No se pudo confirmar la reserva"
  },
  66028: {
    status: 409,
    code: "CART_CONVERSION_FAILED",
    message: "No se pudo convertir el carrito"
  }
};

export async function confirmCheckoutController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const parsed = confirmCheckoutSchema.safeParse(
    req.body
  );

  if (!parsed.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de checkout invalidos"
    });
    return;
  }

  const actor = res.locals.auth as
    | { id: number; role: string }
    | undefined;

  if (!actor) {
    res.status(401).json({
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });
    return;
  }

  try {
    const data = await confirmCustomerCheckout(
      actor.id,
      parsed.data
    );

    res.status(200).json({
      message: "Checkout confirmado correctamente",
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

    const mapped = sqlNumber === undefined
      ? undefined
      : businessErrors[sqlNumber];

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
