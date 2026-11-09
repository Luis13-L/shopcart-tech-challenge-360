import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  listAdminUsersSchema
} from "./users.list.schema.js";

import {
  listAdminUsersService
} from "./users.list.service.js";

// ==========================================
// ERRORES DE NEGOCIO SQL SERVER
// ==========================================

interface BusinessError {
  status: number;
  code: string;
  message: string;
}

const businessErrors: Record<
  number,
  BusinessError
> = {
  79710: {
    status: 403,
    code: "FORBIDDEN",
    message: "Administrador no autorizado"
  },

  79711: {
    status: 400,
    code: "INVALID_PAGINATION",
    message: "Parametros de paginacion invalidos"
  },

  79712: {
    status: 400,
    code: "INVALID_ROLE",
    message: "Filtro de rol invalido"
  }
};

// ==========================================
// GET /api/admin/users
// ==========================================

export async function listAdminUsersController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  // El ID procede del token JWT validado
  // por requireAuth, nunca del cliente.

  const actor = res.locals.auth as
    | {
        id: number;
        role: string;
      }
    | undefined;

  if (
    !actor ||
    !Number.isSafeInteger(actor.id) ||
    actor.id <= 0
  ) {
    res.status(401).json({
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });

    return;
  }

  // ========================================
  // VALIDAR FILTROS
  // ========================================

  const parsed = listAdminUsersSchema.safeParse(
    req.query
  );

  if (!parsed.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Filtros de usuarios invalidos"
    });

    return;
  }

  // ========================================
  // CONSULTAR USUARIOS
  // ========================================

  try {
    const data = await listAdminUsersService(
      actor.id,
      parsed.data
    );

    res.status(200).json({
      message: "Usuarios consultados correctamente",
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
