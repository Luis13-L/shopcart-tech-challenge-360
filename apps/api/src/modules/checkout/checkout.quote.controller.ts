import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  quoteCouponSchema
} from "./checkout.quote.schema.js";

import {
  quoteCustomerCoupon
} from "./checkout.quote.service.js";

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
  // Parametros y autorizacion

  79610: {
    status: 400,
    code: "INVALID_USER",
    message: "Usuario invalido"
  },

  79611: {
    status: 400,
    code: "INVALID_CART",
    message: "Carrito invalido"
  },

  79612: {
    status: 403,
    code: "FORBIDDEN",
    message: "Cliente no autorizado"
  },

  79613: {
    status: 404,
    code: "CART_UNAVAILABLE",
    message: "Carrito no disponible"
  },

  79614: {
    status: 409,
    code: "EMPTY_CART",
    message: "El carrito no tiene productos disponibles"
  },

  79615: {
    status: 409,
    code: "PRODUCT_UNAVAILABLE",
    message: "Hay productos no disponibles"
  },

  // Cupones

  66029: {
    status: 400,
    code: "INVALID_COUPON_CODE",
    message: "Codigo de cupon invalido"
  },

  66030: {
    status: 404,
    code: "COUPON_NOT_FOUND",
    message: "Cupon inexistente o inactivo"
  },

  66031: {
    status: 409,
    code: "COUPON_EXPIRED",
    message: "Cupon fuera de vigencia"
  },

  66032: {
    status: 409,
    code: "COUPON_MINIMUM_NOT_MET",
    message: "No se alcanza el monto minimo del cupon"
  },

  66033: {
    status: 409,
    code: "COUPON_EXHAUSTED",
    message: "Cupon sin usos disponibles"
  },

  66034: {
    status: 409,
    code: "COUPON_CUSTOMER_LIMIT",
    message: "Limite de usos por cliente alcanzado"
  },

  66035: {
    status: 409,
    code: "COUPON_NOT_APPLICABLE",
    message: "El cupon no genera descuento"
  },

  66036: {
    status: 409,
    code: "COUPON_TYPE_UNSUPPORTED",
    message: "Tipo de descuento no soportado"
  },

  66037: {
    status: 409,
    code: "COUPON_CATEGORY_NOT_APPLICABLE",
    message: "El cupon no aplica a estos productos"
  }
};

// ==========================================
// POST /api/checkout/quote
// ==========================================

export async function quoteCheckoutController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const parsed = quoteCouponSchema.safeParse(
    req.body
  );

  if (!parsed.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de cotizacion invalidos"
    });

    return;
  }

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

  try {
    const data = await quoteCustomerCoupon(
      actor.id,
      parsed.data
    );

    res.status(200).json({
      message: "Cupon cotizado correctamente",
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
