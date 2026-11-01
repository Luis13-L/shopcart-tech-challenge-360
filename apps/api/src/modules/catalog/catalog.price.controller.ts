import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  variantPriceParamsSchema,
  updateVariantPriceSchema
} from "./catalog.price.schema.js";

import {
  updateVariantPrice
} from "./catalog.price.service.js";

const businessErrors: Record<
  number,
  {
    status: number;
    code: string;
    message: string;
  }
> = {
  75000: {
    status: 400,
    code: "INVALID_VARIANT",
    message: "ID de variante invalido"
  },
  75001: {
    status: 400,
    code: "INVALID_PRICE",
    message: "Precio invalido"
  },
  75002: {
    status: 403,
    code: "FORBIDDEN",
    message: "Permisos administrativos insuficientes"
  },
  75003: {
    status: 404,
    code: "VARIANT_NOT_FOUND",
    message: "Variante inexistente o inactiva"
  },
  75004: {
    status: 409,
    code: "PRICE_UPDATE_FAILED",
    message: "No se pudo actualizar el precio"
  },
  75005: {
    status: 400,
    code: "INVALID_REASON",
    message: "Debe indicar un motivo"
  }
};

export async function updateVariantPriceController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {

  const params = variantPriceParamsSchema.safeParse(
    req.params
  );

  const body = updateVariantPriceSchema.safeParse(
    req.body
  );

  if (!params.success || !body.success) {
    res.status(400).json({
      code: "VALIDATION_ERROR",
      message: "Datos de precio invalidos"
    });
    return;
  }

  const actor = res.locals.auth as
    | { id: number; role: string }
    | undefined;

  if (!actor) {
    res.status(401).json({
      code: "UNAUTHORIZED",
      message: "Autenticacion requerida"
    });
    return;
  }

  try {
    const data = await updateVariantPrice(
      params.data.id,
      actor.id,
      body.data
    );

    res.status(200).json({
      message: data.actualizado
        ? "Precio actualizado correctamente"
        : "El precio ya tenia ese valor",
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
