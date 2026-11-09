import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  createAdminUserSchema
} from "./users.create.schema.js";

import {
  createAdminUserService
} from "./users.create.service.js";

// ==========================================
// ERRORES DE NEGOCIO
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
  79810: {
    status: 400,
    code: "INVALID_ACTOR",
    message: "Usuario administrador invalido"
  },

  79811: {
    status: 400,
    code: "INVALID_EMAIL",
    message: "Correo electronico invalido"
  },

  79812: {
    status: 400,
    code: "INVALID_ROLE",
    message: "Rol de usuario invalido"
  },

  79813: {
    status: 400,
    code: "INVALID_PASSWORD_HASH",
    message: "No se pudo procesar la contrasena"
  },

  79814: {
    status: 403,
    code: "FORBIDDEN",
    message: "Administrador no autorizado"
  },

  79815: {
    status: 409,
    code: "ROLE_NOT_FOUND",
    message: "El rol solicitado no existe"
  },

  79816: {
    status: 409,
    code: "EMAIL_ALREADY_EXISTS",
    message: "El correo ya esta registrado"
  },

  2601: {
    status: 409,
    code: "EMAIL_ALREADY_EXISTS",
    message: "El correo ya esta registrado"
  },

  2627: {
    status: 409,
    code: "EMAIL_ALREADY_EXISTS",
    message: "El correo ya esta registrado"
  }
};

// ==========================================
// POST /api/admin/users
// ==========================================

export async function createAdminUserController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  // ========================================
  // 1. OBTENER ADMINISTRADOR AUTENTICADO
  // ========================================

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
  // 2. VALIDAR DATOS DE ENTRADA
  // ========================================

  const parsed = createAdminUserSchema.safeParse(
    req.body
  );

  if (!parsed.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de usuario invalidos"
    });

    return;
  }

  // ========================================
  // 3. CREAR USUARIO
  // ========================================

  try {
    const data = await createAdminUserService(
      actor.id,
      parsed.data
    );

    res.status(201).json({
      message: "Usuario creado correctamente",
      data
    });

  } catch (error) {
    // ======================================
    // 4. MAPEAR ERRORES DE SQL SERVER
    // ======================================

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

    // Dejar errores desconocidos al
    // middleware centralizado.
    next(error);
  }
}
