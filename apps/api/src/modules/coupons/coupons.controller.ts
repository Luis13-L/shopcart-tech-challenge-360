import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  couponBodySchema,
  couponIdParamsSchema,
  couponListQuerySchema,
  couponStatusSchema,
  couponCategorySchema
} from "./coupons.schema.js";

import {
  couponsService
} from "./coupons.service.js";

// ==========================================
// ERRORES DE NEGOCIO DE SQL SERVER
// ==========================================

const businessErrors: Record<
  number,
  {
    status: number;
    code: string;
    message: string;
  }
> = {

  // ========================================
  // AUTORIZACION
  // ========================================

  71001: {
    status: 403,
    code: "FORBIDDEN",
    message:
      "Solo el Administrador puede gestionar cupones"
  },

  // ========================================
  // VALIDACIONES DEL CUPON
  // ========================================

  71010: {
    status: 400,
    code: "INVALID_CODE",
    message: "Codigo de cupon invalido"
  },

  71011: {
    status: 400,
    code: "INVALID_DISCOUNT_TYPE",
    message: "Tipo de descuento invalido"
  },

  71012: {
    status: 400,
    code: "INVALID_VALUES",
    message: "Valores, limites o fechas invalidos"
  },

  71013: {
    status: 409,
    code: "COUPON_DUPLICATED",
    message: "Ya existe un cupon con ese codigo"
  },

  71014: {
    status: 404,
    code: "COUPON_NOT_FOUND",
    message: "Cupon no encontrado"
  },

  71015: {
    status: 400,
    code: "INVALID_COUPON_ID",
    message: "ID de cupon invalido"
  },

  71016: {
    status: 400,
    code: "INVALID_STATUS",
    message: "Estado del cupon invalido"
  },

  // ========================================
  // LIMITES Y RESTRICCIONES
  // ========================================

  71017: {
    status: 409,
    code: "GLOBAL_LIMIT_TOO_LOW",
    message:
      "El limite global no puede ser inferior a los usos"
  },

  71018: {
    status: 409,
    code: "USED_COUPON_IMMUTABLE",
    message:
      "No pueden cambiarse las condiciones de un cupon utilizado"
  },

  71019: {
    status: 409,
    code: "CUSTOMER_LIMIT_TOO_LOW",
    message:
      "Limite por cliente inferior a los usos existentes"
  },

  // ========================================
  // RF-05: CUPONES POR CATEGORIA
  // ========================================

  71020: {
    status: 400,
    code: "INVALID_CATEGORY",
    message: "Categoria invalida"
  },

  71021: {
    status: 404,
    code: "CATEGORY_NOT_FOUND",
    message: "Categoria inexistente o inactiva"
  },

  71022: {
    status: 409,
    code: "COUPON_ALREADY_USED",
    message:
      "No se puede cambiar la categoria de un cupon utilizado"
  },

  // ========================================
  // ERRORES DE DUPLICIDAD SQL SERVER
  // ========================================

  2601: {
    status: 409,
    code: "COUPON_DUPLICATED",
    message: "Codigo de cupon duplicado"
  },

  2627: {
    status: 409,
    code: "COUPON_DUPLICATED",
    message: "Codigo de cupon duplicado"
  }
};

// ==========================================
// FUNCIONES AUXILIARES
// ==========================================

function getActorId(
  res: Response
): number | undefined {

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
    return undefined;
  }

  return actor.id;
}

// ==========================================
// RESPUESTA DE VALIDACION
// ==========================================

function rejectValidation(
  res: Response
): void {

  res.status(400).json({
    code: "VALIDATION_ERROR",
    message: "Datos de cupon invalidos"
  });
}

// ==========================================
// RESPUESTA NO AUTORIZADO
// ==========================================

function rejectUnauthorized(
  res: Response
): void {

  res.status(401).json({
    code: "UNAUTHORIZED",
    message: "Autenticacion requerida"
  });
}

// ==========================================
// MANEJO CENTRALIZADO DE RESPUESTAS
// ==========================================

async function sendResult(
  res: Response,
  next: NextFunction,
  task: () => Promise<unknown>,
  status = 200
): Promise<void> {

  try {

    const data = await task();

    res.status(status).json({
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

// ==========================================
// POST /api/coupons
// CREAR CUPON
// ==========================================

export async function createCouponController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const userId = getActorId(res);

  if (!userId) {
    rejectUnauthorized(res);
    return;
  }

  const parsed = couponBodySchema.safeParse(
    req.body
  );

  if (!parsed.success) {
    rejectValidation(res);
    return;
  }

  await sendResult(
    res,
    next,
    () => couponsService.create(
      userId,
      parsed.data
    ),
    201
  );
}

// ==========================================
// GET /api/coupons
// LISTAR CUPONES
// ==========================================

export async function listCouponsController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const userId = getActorId(res);

  if (!userId) {
    rejectUnauthorized(res);
    return;
  }

  const parsed = couponListQuerySchema.safeParse(
    req.query
  );

  if (!parsed.success) {
    rejectValidation(res);
    return;
  }

  const onlyActive =
    parsed.data.soloActivos === undefined
      ? undefined
      : parsed.data.soloActivos === "true";

  await sendResult(
    res,
    next,
    () => couponsService.list(
      userId,
      onlyActive
    )
  );
}

// ==========================================
// GET /api/coupons/:id
// CONSULTAR CUPON POR ID
// ==========================================

export async function getCouponController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const userId = getActorId(res);

  if (!userId) {
    rejectUnauthorized(res);
    return;
  }

  const parsed = couponIdParamsSchema.safeParse(
    req.params
  );

  if (!parsed.success) {
    rejectValidation(res);
    return;
  }

  await sendResult(
    res,
    next,
    () => couponsService.get(
      userId,
      parsed.data.id
    )
  );
}

// ==========================================
// PUT /api/coupons/:id
// ACTUALIZAR CUPON
// ==========================================

export async function updateCouponController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const userId = getActorId(res);

  if (!userId) {
    rejectUnauthorized(res);
    return;
  }

  const params = couponIdParamsSchema.safeParse(
    req.params
  );

  const body = couponBodySchema.safeParse(
    req.body
  );

  if (!params.success || !body.success) {
    rejectValidation(res);
    return;
  }

  await sendResult(
    res,
    next,
    () => couponsService.update(
      userId,
      params.data.id,
      body.data
    )
  );
}

// ==========================================
// PATCH /api/coupons/:id/status
// ACTIVAR O DESACTIVAR CUPON
// ==========================================

export async function changeCouponStatusController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const userId = getActorId(res);

  if (!userId) {
    rejectUnauthorized(res);
    return;
  }

  const params = couponIdParamsSchema.safeParse(
    req.params
  );

  const body = couponStatusSchema.safeParse(
    req.body
  );

  if (!params.success || !body.success) {
    rejectValidation(res);
    return;
  }

  await sendResult(
    res,
    next,
    () => couponsService.setActive(
      userId,
      params.data.id,
      body.data.activo
    )
  );
}

// ==========================================
// GET /api/coupons/:id/uses
// CONSULTAR HISTORIAL DE USOS
// ==========================================

export async function listCouponUsesController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const userId = getActorId(res);

  if (!userId) {
    rejectUnauthorized(res);
    return;
  }

  const parsed = couponIdParamsSchema.safeParse(
    req.params
  );

  if (!parsed.success) {
    rejectValidation(res);
    return;
  }

  await sendResult(
    res,
    next,
    () => couponsService.uses(
      userId,
      parsed.data.id
    )
  );
}

// ==========================================
// PATCH /api/coupons/:id/category
// RF-05: ASIGNAR CATEGORIA AL CUPON
// ==========================================

export async function assignCouponCategoryController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const userId = getActorId(res);

  if (!userId) {
    rejectUnauthorized(res);
    return;
  }

  // Validar el ID del cupon.
  const params = couponIdParamsSchema.safeParse(
    req.params
  );

  // Validar la categoria.
  const body = couponCategorySchema.safeParse(
    req.body
  );

  if (!params.success || !body.success) {
    rejectValidation(res);
    return;
  }

  // La regla de negocio y permisos
  // se comprueban dentro del SP.
  await sendResult(
    res,
    next,
    () => couponsService.setCategory(
      userId,
      params.data.id,
      body.data.idCategoria
    )
  );
}
