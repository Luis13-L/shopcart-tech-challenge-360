import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  reactivateProductIdSchema
} from "./catalog.admin.reactivate.schema.js";

import {
  reactivateCatalogProduct
} from "./catalog.admin.reactivate.service.js";

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

  80210: {
    status: 403,
    code: "FORBIDDEN",
    message: "Administrador no autorizado"
  },

  80211: {
    status: 400,
    code: "INVALID_PRODUCT_ID",
    message: "ID de producto invalido"
  },

  80212: {
    status: 404,
    code: "PRODUCT_NOT_FOUND",
    message: "Producto no encontrado"
  },

  80213: {
    status: 409,
    code: "CATEGORY_INACTIVE",
    message:
      "No se puede reactivar un producto " +
      "de una categoria inactiva"
  },

  80214: {
    status: 409,
    code: "HISTORY_NOT_AVAILABLE",
    message:
      "No existe un historial confiable " +
      "para restaurar las variantes"
  },

  80215: {
    status: 409,
    code: "NO_ACTIVE_VARIANTS",
    message:
      "El producto no tenia variantes " +
      "activas antes de desactivarse"
  },

  80216: {
    status: 409,
    code: "PRODUCT_STATE_CONFLICT",
    message:
      "El estado del producto o sus variantes " +
      "requiere revision administrativa"
  }
};

// ==========================================
// PATCH /api/admin/products/:id/reactivate
// ==========================================

export async function reactivateProductController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  // ========================================
  // 1. VALIDAR ID DEL PRODUCTO
  // ========================================

  const validation =
    reactivateProductIdSchema.safeParse(
      req.params.id
    );

  if (!validation.success) {
    res.status(400).json({
      status: 400,
      code: "VALIDATION_ERROR",
      message: "ID de producto invalido"
    });

    return;
  }

  // ========================================
  // 2. OBTENER ADMINISTRADOR AUTENTICADO
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
      status: 401,
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });

    return;
  }

  // ========================================
  // 3. REACTIVAR PRODUCTO
  // ========================================

  try {

    const product =
      await reactivateCatalogProduct(
        validation.data,
        actor.id
      );

    res.status(200).json({
      message: product.reutilizado
        ? "El producto ya estaba activo"
        : "Producto reactivado correctamente",

      data: product
    });

  } catch (error) {

    // ======================================
    // 4. MAPEAR ERRORES SQL SERVER
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
        status: mapped.status,
        code: mapped.code,
        message: mapped.message
      });

      return;
    }

    // ======================================
    // 5. ERROR INESPERADO
    // ======================================

    next(error);
  }
}
