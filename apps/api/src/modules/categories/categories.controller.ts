import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  createCategorySchema,
  updateCategorySchema,
  categoryStatusSchema,
  categoryIdParamsSchema
} from "./categories.schema.js";

import {
  categoriesService
} from "./categories.service.js";

const businessErrors: Record<
  number,
  {
    status: number;
    code: string;
    message: string;
  }
> = {
  76010: {
    status: 400,
    code: "INVALID_NAME",
    message: "Nombre de categoria invalido"
  },
  76011: {
    status: 403,
    code: "FORBIDDEN",
    message: "Permisos insuficientes"
  },
  76012: {
    status: 409,
    code: "CATEGORY_DUPLICATED",
    message: "La categoria ya existe"
  },
  76013: {
    status: 400,
    code: "INVALID_FILTER",
    message: "Filtro invalido"
  },
  76014: {
    status: 400,
    code: "INVALID_CATEGORY_ID",
    message: "ID de categoria invalido"
  },
  76015: {
    status: 400,
    code: "INVALID_DESCRIPTION_FLAG",
    message: "Indicador de descripcion invalido"
  },
  76016: {
    status: 400,
    code: "EMPTY_UPDATE",
    message: "Debe proporcionar algun cambio"
  },
  76017: {
    status: 404,
    code: "CATEGORY_NOT_FOUND",
    message: "Categoria no encontrada"
  },
  76018: {
    status: 409,
    code: "CATEGORY_HAS_PRODUCTS",
    message:
      "No puede desactivar una categoria con productos activos"
  },
  76019: {
    status: 400,
    code: "INVALID_STATUS",
    message: "Estado invalido"
  },
  2601: {
    status: 409,
    code: "CATEGORY_DUPLICATED",
    message: "La categoria ya existe"
  },
  2627: {
    status: 409,
    code: "CATEGORY_DUPLICATED",
    message: "La categoria ya existe"
  }
};

function getActorId(
  res: Response
): number | undefined {
  const actor = res.locals.auth as
    | { id: number; role: string }
    | undefined;

  return actor?.id;
}

function rejectValidation(res: Response): void {
  res.status(400).json({
    code: "VALIDATION_ERROR",
    message: "Datos de categoria invalidos"
  });
}

function rejectUnauthorized(res: Response): void {
  res.status(401).json({
    code: "UNAUTHORIZED",
    message: "Autenticacion requerida"
  });
}

async function sendResult(
  res: Response,
  next: NextFunction,
  action: () => Promise<unknown>,
  status = 200
): Promise<void> {
  try {
    const data = await action();

    res.status(status).json({ data });

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
// GET /api/catalog/categories
// ==========================================

export async function listPublicCategoriesController(
  _req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  await sendResult(
    res,
    next,
    () => categoriesService.listPublic()
  );
}

// ==========================================
// GET /api/catalog/categories/admin
// ==========================================

export async function listAdminCategoriesController(
  _req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actorId = getActorId(res);

  if (!actorId) {
    rejectUnauthorized(res);
    return;
  }

  await sendResult(
    res,
    next,
    () => categoriesService.listAdmin(actorId)
  );
}

// ==========================================
// POST /api/catalog/categories
// ==========================================

export async function createCategoryController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actorId = getActorId(res);

  if (!actorId) {
    rejectUnauthorized(res);
    return;
  }

  const parsed = createCategorySchema.safeParse(
    req.body
  );

  if (!parsed.success) {
    rejectValidation(res);
    return;
  }

  await sendResult(
    res,
    next,
    () => categoriesService.create(
      actorId,
      parsed.data
    ),
    201
  );
}

// ==========================================
// PATCH /api/catalog/categories/:id
// ==========================================

export async function updateCategoryController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actorId = getActorId(res);

  if (!actorId) {
    rejectUnauthorized(res);
    return;
  }

  const params = categoryIdParamsSchema.safeParse(
    req.params
  );

  const body = updateCategorySchema.safeParse(
    req.body
  );

  if (!params.success || !body.success) {
    rejectValidation(res);
    return;
  }

  await sendResult(
    res,
    next,
    () => categoriesService.update(
      actorId,
      params.data.id,
      body.data
    )
  );
}

// ==========================================
// PATCH /api/catalog/categories/:id/status
// ==========================================

export async function changeCategoryStatusController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actorId = getActorId(res);

  if (!actorId) {
    rejectUnauthorized(res);
    return;
  }

  const params = categoryIdParamsSchema.safeParse(
    req.params
  );

  const body = categoryStatusSchema.safeParse(
    req.body
  );

  if (!params.success || !body.success) {
    rejectValidation(res);
    return;
  }

  await sendResult(
    res,
    next,
    () => categoriesService.setActive(
      actorId,
      params.data.id,
      body.data.activa
    )
  );
}
