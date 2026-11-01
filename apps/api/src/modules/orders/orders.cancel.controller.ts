import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  cancelOrderParamsSchema,
  cancelOrderBodySchema
} from "./orders.cancel.schema.js";

import {
  cancelCustomerOrder
} from "./orders.cancel.service.js";

const businessErrors: Record<
  number,
  {
    status: number;
    code: string;
    message: string;
  }
> = {
  68010: {
    status: 400,
    code: "INVALID_ORDER",
    message: "Pedido invalido"
  },
  68011: {
    status: 400,
    code: "INVALID_USER",
    message: "Usuario invalido"
  },
  68012: {
    status: 400,
    code: "INVALID_REASON",
    message: "Debe indicar un motivo de cancelacion"
  },
  68013: {
    status: 403,
    code: "FORBIDDEN",
    message: "Usuario no autorizado"
  },
  68014: {
    status: 404,
    code: "ORDER_NOT_FOUND",
    message: "Pedido no encontrado"
  },
  68015: {
    status: 403,
    code: "FORBIDDEN",
    message: "No tienes permisos para cancelar este pedido"
  },
  68016: {
    status: 409,
    code: "ORDER_NOT_CANCELLABLE",
    message: "El pedido ya no puede cancelarse"
  },
  68017: {
    status: 409,
    code: "PAYMENT_NOT_CANCELLABLE",
    message: "El pago no admite cancelacion"
  },
  68018: {
    status: 409,
    code: "EMPTY_ORDER",
    message: "El pedido no tiene detalles"
  },
  68019: {
    status: 409,
    code: "PREVIOUS_RETURNS",
    message: "El pedido tiene devoluciones previas"
  },
  68020: {
    status: 409,
    code: "INVENTORY_NOT_FOUND",
    message: "No existe inventario para una variante"
  },
  68021: {
    status: 409,
    code: "INVENTORY_LIMIT_EXCEEDED",
    message: "El reintegro supera el limite de inventario"
  }
};

export async function cancelOrderController(
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
      message: "Autenticacion requerida"
    });
    return;
  }

  const params = cancelOrderParamsSchema.safeParse(
    req.params
  );

  const body = cancelOrderBodySchema.safeParse(
    req.body
  );

  if (!params.success || !body.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de cancelacion invalidos"
    });
    return;
  }

  try {
    const data = await cancelCustomerOrder(
      params.data.id,
      actor.id,
      body.data.motivo
    );

    res.status(200).json({
      message: data.yaCancelado
        ? "El pedido ya estaba cancelado"
        : "Pedido cancelado correctamente",
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
