import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  userSecurityParamsSchema,
  changeUserRoleSchema,
  changeUserStatusSchema
} from "./users.security.schema.js";

import {
  usersSecurityService
} from "./users.security.service.js";

// ==========================================
// ERRORES SQL SERVER
// ==========================================

const businessErrors: Record<
  number,
  {
    status: number;
    code: string;
    message: string;
  }
> = {
  79910: {
    status: 400,
    code: "INVALID_ACTOR",
    message: "Administrador invalido"
  },

  79911: {
    status: 400,
    code: "INVALID_USER_ID",
    message: "Usuario objetivo invalido"
  },

  79912: {
    status: 400,
    code: "INVALID_OPERATION",
    message: "Indique solo rol o estado"
  },

  79913: {
    status: 400,
    code: "INVALID_ROLE",
    message: "Rol solicitado invalido"
  },

  79914: {
    status: 403,
    code: "FORBIDDEN",
    message: "Administrador no autorizado"
  },

  79915: {
    status: 409,
    code: "SELF_MODIFICATION_FORBIDDEN",
    message: "No puedes modificar tu propio rol o estado"
  },

  79916: {
    status: 404,
    code: "USER_NOT_FOUND",
    message: "Usuario no encontrado"
  },

  79917: {
    status: 409,
    code: "LAST_ACTIVE_ADMIN",
    message: "No puedes quitar el ultimo Administrador activo"
  },

  79918: {
    status: 409,
    code: "ROLE_NOT_FOUND",
    message: "El rol solicitado no existe"
  },

  79919: {
    status: 409,
    code: "UPDATE_FAILED",
    message: "No se pudo actualizar el usuario"
  }
};

// ==========================================
// FUNCIONES COMPARTIDAS
// ==========================================

function getActorId(
  res: Response
): number | null {
  const actor = res.locals.auth as
    | { id: number; role: string }
    | undefined;

  if (
    !actor ||
    !Number.isSafeInteger(actor.id) ||
    actor.id <= 0
  ) {
    return null;
  }

  return actor.id;
}

async function sendResult(
  res: Response,
  next: NextFunction,
  action: () => Promise<unknown>,
  message: string
): Promise<void> {
  try {
    const data = await action();

    res.status(200).json({
      message,
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

// ==========================================
// PATCH /api/admin/users/:id/role
// ==========================================

export async function changeUserRoleController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actorId = getActorId(res);

  if (actorId === null) {
    res.status(401).json({
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });

    return;
  }

  const params =
    userSecurityParamsSchema.safeParse(
      req.params
    );

  const body =
    changeUserRoleSchema.safeParse(
      req.body
    );

  if (!params.success || !body.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de cambio de rol invalidos"
    });

    return;
  }

  await sendResult(
    res,
    next,
    () => usersSecurityService.changeRole(
      actorId,
      params.data.id,
      body.data.rol
    ),
    "Rol actualizado correctamente"
  );
}

// ==========================================
// PATCH /api/admin/users/:id/status
// ==========================================

export async function changeUserStatusController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actorId = getActorId(res);

  if (actorId === null) {
    res.status(401).json({
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });

    return;
  }

  const params =
    userSecurityParamsSchema.safeParse(
      req.params
    );

  const body =
    changeUserStatusSchema.safeParse(
      req.body
    );

  if (!params.success || !body.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de cambio de estado invalidos"
    });

    return;
  }

  await sendResult(
    res,
    next,
    () => usersSecurityService.changeStatus(
      actorId,
      params.data.id,
      body.data.activo
    ),
    "Estado actualizado correctamente"
  );
}
