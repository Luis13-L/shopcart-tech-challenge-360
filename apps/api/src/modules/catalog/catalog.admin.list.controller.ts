import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  listAdminProductsSchema
} from "./catalog.admin.list.schema.js";

import {
  listAdminProductsService
} from "./catalog.admin.list.service.js";

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
  80110: {
    status: 403,
    code: "FORBIDDEN",
    message: "Administrador no autorizado"
  },

  80111: {
    status: 400,
    code: "INVALID_PAGINATION",
    message: "Parametros de paginacion invalidos"
  },

  80112: {
    status: 400,
    code: "INVALID_CATEGORY",
    message: "Categoria invalida"
  }
};

// ==========================================
// GET /api/admin/products
// ==========================================

export async function listAdminProductsController(
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
  // 2. VALIDAR PARAMETROS
  // ========================================

  const parsed = listAdminProductsSchema.safeParse(
    req.query
  );

  if (!parsed.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message:
        "Filtros de productos invalidos"
    });

    return;
  }

  // ========================================
  // 3. CONSULTAR PRODUCTOS
  // ========================================

  try {
    const data = await listAdminProductsService(
      actor.id,
      parsed.data
    );

    res.status(200).json({
      message:
        "Productos administrativos consultados correctamente",
      data
    });

  } catch (error) {

    // ======================================
    // 4. INTERPRETAR ERRORES SQL
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

    // ======================================
    // 5. MANEJO GLOBAL DE ERRORES
    // ======================================

    next(error);
  }
}
