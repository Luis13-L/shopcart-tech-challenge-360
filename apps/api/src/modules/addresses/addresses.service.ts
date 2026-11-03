import type {
  CreateAddressInput
} from "./addresses.schema.js";

import {
  createAddress,
  listAddresses,
  getAddress
} from "./addresses.repository.js";

export const addressesService = {
  create(
    userId: number,
    input: CreateAddressInput
  ) {
    return createAddress(userId, input);
  },

  list(userId: number) {
    return listAddresses(userId);
  },

  get(userId: number, addressId: number) {
    return getAddress(userId, addressId);
  }
};
