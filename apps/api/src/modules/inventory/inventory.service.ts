import type {
  InventoryMovementInput,
  InventoryKardexQuery
} from "./inventory.schema.js";

import {
  registerMovement,
  getInventoryStock,
  getInventoryKardex
} from "./inventory.repository.js";

export const inventoryService = {
  register(
    actorId: number,
    input: InventoryMovementInput
  ) {
    return registerMovement(actorId, input);
  },

  stock(actorId: number, variantId: number) {
    return getInventoryStock(actorId, variantId);
  },

  kardex(
    actorId: number,
    variantId: number,
    query: InventoryKardexQuery
  ) {
    return getInventoryKardex(
      actorId,
      variantId,
      query
    );
  }
};
