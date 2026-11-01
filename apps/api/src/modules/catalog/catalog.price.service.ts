import type {
  UpdateVariantPriceInput
} from "./catalog.price.schema.js";

import {
  updateVariantPriceInDatabase
} from "./catalog.price.repository.js";

function formatMoney(
  value: number | string
): string {
  const amount = Number(value);

  if (!Number.isFinite(amount)) {
    throw new Error("Precio SQL invalido");
  }

  return amount.toFixed(2);
}

export async function updateVariantPrice(
  variantId: number,
  actorId: number,
  input: UpdateVariantPriceInput
) {
  const row = await updateVariantPriceInDatabase(
    variantId,
    actorId,
    input
  );

  return {
    idVariante: row.IDVariante,
    idProducto: row.IDProducto,
    sku: row.SKU,
    precioAnterior: formatMoney(
      row.PrecioAnterior
    ),
    precioActual: formatMoney(
      row.PrecioActual
    ),
    actualizado: Boolean(
      row.Actualizado
    ),
    fechaCambio: row.FechaCambio
      ? new Date(row.FechaCambio).toISOString()
      : null
  };
}
