
import type {
  UpdateProductInput
} from "./catalog.update.schema.js";

import {
  updateProductInDatabase
} from "./catalog.update.repository.js";

export async function updateCatalogProduct(
  productId: number,
  input: UpdateProductInput,
  actorId: number
) {
  const product = await updateProductInDatabase(
    productId,
    input,
    actorId
  );

  return {
    idProducto: product.IDProducto,
    idCategoria: product.IDCategoria,
    nombre: product.Nombre,
    descripcion: product.Descripcion,
    activo: product.Activo
  };
}
