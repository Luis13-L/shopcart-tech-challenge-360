import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  salesReportSchema,
  dateRangeSchema,
  ordersReportSchema
} from "./reports.schema.js";

import {
  reportsService
} from "./reports.service.js";

// ==========================================
// MAPEO DE ERRORES SQL
// ==========================================

const businessErrors: Record<
  number,
  {
    status: number;
    code: string;
    message: string;
  }
> = {
  72010: {
    status: 403,
    code: "FORBIDDEN",
    message: "No autorizado para consultar reportes"
  },
  72011: {
    status: 400,
    code: "INVALID_DATE_RANGE",
    message: "Rango de fechas invalido"
  },
  72012: {
    status: 400,
    code: "INVALID_GROUPING",
    message: "Agrupacion invalida"
  },
  72110: {
    status: 403,
    code: "FORBIDDEN",
    message: "No autorizado para consultar pedidos"
  },
  72111: {
    status: 400,
    code: "INVALID_PAGE",
    message: "Numero de pagina invalido"
  },
  72112: {
    status: 400,
    code: "INVALID_PAGE_SIZE",
    message: "Tamano de pagina invalido"
  },
  72113: {
    status: 400,
    code: "INVALID_CUSTOMER",
    message: "Cliente invalido"
  },
  72114: {
    status: 400,
    code: "INVALID_STATUS",
    message: "Estado de pedido invalido"
  },
  72115: {
    status: 400,
    code: "INVALID_DATE_RANGE",
    message: "Rango de fechas invalido"
  },
  72116: {
    status: 400,
    code: "INVALID_END_DATE",
    message: "Fecha final fuera de rango"
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

function rejectUnauthorized(
  res: Response
): void {
  res.status(401).json({
    code: "UNAUTHORIZED",
    message: "Autenticacion requerida"
  });
}

function rejectValidation(
  res: Response
): void {
  res.status(400).json({
    code: "VALIDATION_ERROR",
    message: "Filtros de reporte invalidos"
  });
}

async function executeReport(
  res: Response,
  next: NextFunction,
  action: () => Promise<unknown>
): Promise<void> {
  try {
    const data = await action();

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

// ==========================================
// GET /api/reports/sales
// ==========================================

export async function salesReportController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const userId = getActorId(res);

  if (!userId) {
    rejectUnauthorized(res);
    return;
  }

  const parsed = salesReportSchema.safeParse(
    req.query
  );

  if (!parsed.success) {
    rejectValidation(res);
    return;
  }

  await executeReport(
    res,
    next,
    () => reportsService.sales(
      userId,
      parsed.data
    )
  );
}

// ==========================================
// GET /api/reports/categories
// ==========================================

export async function categoriesReportController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const userId = getActorId(res);

  if (!userId) {
    rejectUnauthorized(res);
    return;
  }

  const parsed = dateRangeSchema.safeParse(
    req.query
  );

  if (!parsed.success) {
    rejectValidation(res);
    return;
  }

  await executeReport(
    res,
    next,
    () => reportsService.categories(
      userId,
      parsed.data
    )
  );
}

// ==========================================
// GET /api/reports/top-products
// ==========================================

export async function topProductsReportController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const userId = getActorId(res);

  if (!userId) {
    rejectUnauthorized(res);
    return;
  }

  const parsed = dateRangeSchema.safeParse(
    req.query
  );

  if (!parsed.success) {
    rejectValidation(res);
    return;
  }

  await executeReport(
    res,
    next,
    () => reportsService.topProducts(
      userId,
      parsed.data
    )
  );
}

// ==========================================
// GET /api/orders
// ADMINISTRADOR Y OPERADOR
// ==========================================

export async function listOrdersReportController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const userId = getActorId(res);

  if (!userId) {
    rejectUnauthorized(res);
    return;
  }

  const parsed = ordersReportSchema.safeParse(
    req.query
  );

  if (!parsed.success) {
    rejectValidation(res);
    return;
  }

  await executeReport(
    res,
    next,
    () => reportsService.orders(
      userId,
      parsed.data
    )
  );
}
