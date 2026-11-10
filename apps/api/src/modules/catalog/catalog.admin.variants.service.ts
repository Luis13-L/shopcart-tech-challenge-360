import type {
  ListAdminVariantsInput,
  CreateAdminVariantInput,
  ChangeVariantStatusInput
} from "./catalog.admin.variants.schema.js";

import {
  findAdminVariants,
  insertAdminVariant,
  setAdminVariantStatus
} from "./catalog.admin.variants.repository.js";

export function listAdminVariantsService(
  actorId: number,
  input: ListAdminVariantsInput
) {
  return findAdminVariants(actorId, input);
}

export function createAdminVariantService(
  actorId: number,
  input: CreateAdminVariantInput
) {
  return insertAdminVariant(actorId, input);
}

export function changeAdminVariantStatusService(
  actorId: number,
  variantId: number,
  input: ChangeVariantStatusInput
) {
  return setAdminVariantStatus(actorId, variantId, input.activa);
}
