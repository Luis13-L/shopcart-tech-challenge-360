import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  couponBodySchema,
  couponIdParamsSchema,
  couponListQuerySchema,
  couponStatusSchema
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
  71001: {
    status: 403,
    code: "FORBIDDEN",
    message:
      "Solo el Administrador puede gestionar cupones"
  },
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

  return actor?.id;
}

function rejectValidation(
  res: Response
): void {
  res.status(400).json({
    code: "VALIDATION_ERROR",
    message: "Datos de cupon invalidos"
  });
}

function rejectUnauthorized(
  res: Response
): void {
  res.status(401).json({
    code: "UNAUTHORIZED",
    message: "Autenticacion requerida"
  });
}

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
// POST /api/coupons
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
