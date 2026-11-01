import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  orderIdSchema,
  changeOrderStatusSchema
} from "./orders.status.schema.js";

import {
  changeOrderStatus
} from "./orders.status.service.js";

const businessErrors: Record<
  number,
  {
    status: number;
    code: string;
    message: string;
  }
> = {
  67010: {
    status: 400,
    code: "INVALID_ORDER",
    message: "Pedido invalido"
  },
  67011: {
    status: 400,
    code: "INVALID_USER",
    message: "Usuario invalido"
  },
  67012: {
    status: 403,
    code: "FORBIDDEN",
    message: "Usuario sin permisos"
  },
  67013: {
    status: 404,
    code: "ORDER_NOT_FOUND",
    message: "Pedido no encontrado"
  },
  67014: {
    status: 409,
    code: "INVALID_STATUS_TRANSITION",
    message: "Transicion de estado no permitida"
  },
  67015: {
    status: 409,
    code: "ORDER_UPDATE_FAILED",
    message: "No se pudo actualizar el pedido"
  }
};

export async function changeOrderStatusController(
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

  if (
    actor.role !== "Operador" &&
    actor.role !== "Administrador"
  ) {
    res.status(403).json({
      code: "FORBIDDEN",
      message: "No tienes permisos para gestionar pedidos"
    });
    return;
  }

  const params = orderIdSchema.safeParse(
    req.params
  );

  const body = changeOrderStatusSchema.safeParse(
    req.body
  );

  if (!params.success || !body.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de solicitud invalidos"
    });
    return;
  }

  try {
    const data = await changeOrderStatus(
      params.data.id,
      actor.id,
      body.data
    );

    res.status(200).json({
      message: "Estado actualizado correctamente",
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

    const mapped =
      sqlNumber === undefined
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
