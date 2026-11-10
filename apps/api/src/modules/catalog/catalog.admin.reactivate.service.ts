import {
  reactivateProductInDatabase
} from "./catalog.admin.reactivate.repository.js";

// ==========================================
// SERVICIO DE REACTIVACION
// ==========================================

export async function reactivateCatalogProduct(
  productId: number,
  actorId: number
) {

  const product =
    await reactivateProductInDatabase(
      productId,
      actorId
    );

  return {
    idProducto: product.IDProducto,

    nombre: product.Nombre,

    activo:
      product.Activo === true ||
      product.Activo === 1,

    variantesReactivadas:
      product.VariantesReactivadas,

    reutilizado:
      product.Reutilizado === true ||
      product.Reutilizado === 1
  };
}
