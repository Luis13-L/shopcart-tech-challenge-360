import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  returnOrderParamsSchema,
  returnOrderBodySchema
} from "./orders.return.schema.js";

import {
  processOrderReturn
} from "./orders.return.service.js";

const businessErrors: Record<
  number,
  {
    status: number;
    code: string;
    message: string;
  }
> = {
  69010: {
    status: 400,
    code: "INVALID_ORDER",
    message: "Pedido invalido"
  },
  69011: {
    status: 400,
    code: "INVALID_ORDER_DETAIL",
    message: "Detalle de pedido invalido"
  },
  69012: {
    status: 400,
    code: "INVALID_USER",
    message: "Usuario invalido"
  },
  69013: {
    status: 400,
    code: "INVALID_QUANTITY",
    message: "Cantidad invalida"
  },
  69014: {
    status: 400,
    code: "INVALID_REASON",
    message: "Debe indicar un motivo"
  },
  69015: {
    status: 400,
    code: "INVALID_IDEMPOTENCY_KEY",
    message: "Clave de idempotencia invalida"
  },
  69016: {
    status: 403,
    code: "FORBIDDEN",
    message: "Usuario no autorizado"
  },
  69017: {
    status: 404,
    code: "ORDER_NOT_FOUND",
    message: "Pedido no encontrado"
  },
  69018: {
    status: 403,
    code: "FORBIDDEN",
    message: "No tienes permisos sobre este pedido"
  },
  69019: {
    status: 409,
    code: "IDEMPOTENCY_CONFLICT",
    message: "Clave utilizada para otra devolucion"
  },
  69020: {
    status: 409,
    code: "ORDER_NOT_RETURNABLE",
    message: "El pedido no admite devoluciones"
  },
  69022: {
    status: 409,
    code: "PAYMENT_NOT_RETURNABLE",
    message: "El pago no admite devolucion"
  },
  69023: {
    status: 404,
    code: "ORDER_DETAIL_NOT_FOUND",
    message: "Detalle no encontrado en el pedido"
  },
  69024: {
    status: 409,
    code: "RETURN_QUANTITY_EXCEEDED",
    message: "La cantidad supera las unidades pendientes de devolver"
  },
  69025: {
    status: 409,
    code: "INVENTORY_NOT_FOUND",
    message: "No existe inventario para la variante"
  },
  69026: {
    status: 409,
    code: "INVENTORY_LIMIT_EXCEEDED",
    message: "El reintegro supera el limite de inventario"
  },
  69027: {
    status: 409,
    code: "RETURN_DETAIL_UPDATE_FAILED",
    message: "No se pudo actualizar el detalle"
  },
  69028: {
    status: 409,
    code: "INVENTORY_UPDATE_FAILED",
    message: "No se pudo reintegrar el inventario"
  },
  69029: {
    status: 409,
    code: "ORDER_UPDATE_FAILED",
    message: "No se pudo actualizar el pedido"
  },
  69030: {
    status: 409,
    code: "REFUND_UPDATE_FAILED",
    message: "No se pudo registrar el reembolso simulado"
  },
  69031: {
  status: 409,
  code: "ORDER_TOTAL_INCONSISTENT",
  message: "Los importes historicos del pedido no son coherentes"
},
69032: {
  status: 409,
  code: "REFUND_LIMIT_EXCEEDED",
  message: "El reembolso supera el importe pagado"
}

};

export async function returnOrderController(
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

  const params = returnOrderParamsSchema.safeParse(
    req.params
  );

  const body = returnOrderBodySchema.safeParse(
    req.body
  );

  if (!params.success || !body.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de devolucion invalidos"
    });
    return;
  }

  try {
    const data = await processOrderReturn(
      params.data.id,
      actor.id,
      body.data
    );

    res.status(200).json({
      message: data.reutilizado
        ? "Devolucion procesada anteriormente"
        : "Devolucion registrada correctamente",
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
