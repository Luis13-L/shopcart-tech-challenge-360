import {
  deactivateProductInDatabase
} from "./catalog.deactivate.repository.js";

export async function deactivateCatalogProduct(
  productId: number,
  actorId: number
) {
  const product = await deactivateProductInDatabase(
    productId,
    actorId
  );

  return {
    idProducto: product.IDProducto,
    nombre: product.Nombre,
    activo: product.Activo,
    variantesDesactivadas:
      product.VariantesDesactivadas
  };
}
