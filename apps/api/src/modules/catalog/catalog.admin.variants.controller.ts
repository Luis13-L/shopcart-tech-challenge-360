import type { Request, Response, NextFunction } from "express";

import {
  variantIdParamsSchema,
  listAdminVariantsSchema,
  createAdminVariantSchema,
  changeVariantStatusSchema
} from "./catalog.admin.variants.schema.js";

import {
  listAdminVariantsService,
  createAdminVariantService,
  changeAdminVariantStatusService
} from "./catalog.admin.variants.service.js";

interface BusinessError {
  status: number;
  code: string;
  message: string;
}

const errors: Record<number, BusinessError> = {
  80310: { status: 400, code: "INVALID_PRODUCT", message: "Producto invalido" },
  80311: { status: 400, code: "INVALID_SKU", message: "SKU invalido" },
  80312: { status: 400, code: "INVALID_PRICE", message: "Precio invalido" },
  80313: { status: 400, code: "INVALID_ATTRIBUTES", message: "JSON de atributos invalido" },
  80314: { status: 400, code: "INVALID_ATTRIBUTES", message: "Atributos invalidos o duplicados" },
  80315: { status: 403, code: "FORBIDDEN", message: "Administrador no autorizado" },
  80316: { status: 409, code: "PRODUCT_UNAVAILABLE", message: "Producto o categoria inactiva o inexistente" },
  80317: { status: 409, code: "DUPLICATE_SKU", message: "El SKU ya existe" },
  80318: { status: 500, code: "STOCK_INIT_FAILED", message: "No se pudo inicializar la existencia" },
  80410: { status: 403, code: "FORBIDDEN", message: "Administrador no autorizado" },
  80411: { status: 400, code: "INVALID_VARIANT", message: "Variante invalida" },
  80412: { status: 404, code: "VARIANT_NOT_FOUND", message: "Variante no encontrada" },
  80413: { status: 409, code: "PRODUCT_INACTIVE", message: "No se puede activar en un producto o categoria inactiva" },
  80414: { status: 400, code: "INVALID_STATUS", message: "Estado de variante invalido" },
  80415: { status: 409, code: "STATE_CONFLICT", message: "Conflicto al actualizar la variante" },
  80420: { status: 403, code: "FORBIDDEN", message: "Administrador no autorizado" },
  80421: { status: 400, code: "INVALID_PRODUCT", message: "Producto invalido" },
  80422: { status: 400, code: "INVALID_PAGINATION", message: "Paginacion invalida" },
  80423: { status: 404, code: "PRODUCT_NOT_FOUND", message: "Producto no encontrado" }
};

function actorId(res: Response): number | null {
  const principal = res.locals.auth as
    | { id: number; role: string }
    | undefined;
  return principal && Number.isSafeInteger(principal.id) && principal.id > 0
    ? principal.id
    : null;
}

function handleError(error: unknown, res: Response, next: NextFunction): void {
  const number = typeof error === "object" && error !== null &&
    "number" in error && typeof error.number === "number"
      ? error.number : undefined;
  const mapped = number === undefined ? undefined : errors[number];
  if (!mapped) {
    next(error);
    return;
  }
  res.status(mapped.status).json({
    code: mapped.code,
    message: mapped.message
  });
}

// GET /api/admin/variants?idProducto=3&pagina=1&tamanoPagina=10
export async function listAdminVariantsController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actor = actorId(res);
  if (actor === null) {
    res.status(401).json({ code: "UNAUTHORIZED", message: "Autenticacion requerida" });
    return;
  }

  const parsed = listAdminVariantsSchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ code: "VALIDATION_ERROR", message: "Filtros de variantes invalidos" });
    return;
  }

  try {
    const data = await listAdminVariantsService(actor, parsed.data);
    res.status(200).json({ message: "Variantes consultadas correctamente", data });
  } catch (error) {
    handleError(error, res, next);
  }
}

// POST /api/admin/variants
export async function createAdminVariantController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actor = actorId(res);
  if (actor === null) {
    res.status(401).json({ code: "UNAUTHORIZED", message: "Autenticacion requerida" });
    return;
  }

  const parsed = createAdminVariantSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ code: "VALIDATION_ERROR", message: "Datos de variante invalidos" });
    return;
  }

  try {
    const data = await createAdminVariantService(actor, parsed.data);
    res.status(201).json({ message: "Variante creada correctamente", data });
  } catch (error) {
    handleError(error, res, next);
  }
}

// PATCH /api/admin/variants/:id/status
export async function changeAdminVariantStatusController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const actor = actorId(res);
  if (actor === null) {
    res.status(401).json({ code: "UNAUTHORIZED", message: "Autenticacion requerida" });
    return;
  }

  const params = variantIdParamsSchema.safeParse(req.params);
  const body = changeVariantStatusSchema.safeParse(req.body);
  if (!params.success || !body.success) {
    res.status(400).json({ code: "VALIDATION_ERROR", message: "ID o estado de variante invalido" });
    return;
  }

  try {
    const data = await changeAdminVariantStatusService(
      actor, params.data.id, body.data
    );
    res.status(200).json({
      message: data.actualizado
        ? "Estado de variante actualizado"
        : "La variante ya tenia ese estado",
      data
    });
  } catch (error) {
    handleError(error, res, next);
  }
}
