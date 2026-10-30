
import type {
  CreateProductInput
} from "./catalog.create.schema.js";

import {
  insertCatalogProduct
} from "./catalog.create.repository.js";

export async function createCatalogProduct(
  input: CreateProductInput,
  actorId: number
) {
  const product = await insertCatalogProduct(
    input,
    actorId
  );

  return {
    idProducto: product.IDProducto,
    idVariante: product.IDVariante,
    nombre: product.Nombre,
    sku: product.SKU,
    precioActual: Number(
      product.PrecioActual
    ).toFixed(2)
  };
}
