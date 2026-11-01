import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  auditQuerySchema
} from "./audit.schema.js";

import {
  getAuditLogs
} from "./audit.service.js";

const businessErrors: Record<
  number,
  {
    status: number;
    code: string;
    message: string;
  }
> = {
  73020: {
    status: 403,
    code: "FORBIDDEN",
    message: "Solo el Administrador puede consultar la bitacora"
  },
  73021: {
    status: 400,
    code: "INVALID_PAGINATION",
    message: "Paginacion invalida"
  },
  73022: {
    status: 400,
    code: "INVALID_MODULE",
    message: "Modulo invalido"
  },
  73023: {
    status: 400,
    code: "INVALID_USER_FILTER",
    message: "Usuario invalido"
  },
  73024: {
    status: 400,
    code: "INVALID_DATE_RANGE",
    message: "Rango de fechas invalido"
  },
  73025: {
    status: 400,
    code: "INVALID_END_DATE",
    message: "Fecha final fuera de rango"
  }
};

export async function listAuditController(
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

  const parsed = auditQuerySchema.safeParse(
    req.query
  );

  if (!parsed.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Filtros de auditoria invalidos"
    });
    return;
  }

  try {
    const data = await getAuditLogs(
      actor.id,
      parsed.data
    );

    res.status(200).json({ data });

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
