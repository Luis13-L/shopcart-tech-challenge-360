import type {
  ListAdminProductsInput
} from "./catalog.admin.list.schema.js";

import {
  listAdminProducts
} from "./catalog.admin.list.repository.js";

// ==========================================
// SERVICIO ADMINISTRATIVO DE PRODUCTOS
// ==========================================

export async function listAdminProductsService(
  actorId: number,
  input: ListAdminProductsInput
) {
  return listAdminProducts(
    actorId,
    input
  );
}
