import type {
  CustomerOrdersQuery
} from "./orders.customer.schema.js";

import {
  listCustomerOrders,
  getCustomerOrder
} from "./orders.customer.repository.js";

export const customerOrdersService = {
  list(
    userId: number,
    query: CustomerOrdersQuery
  ) {
    return listCustomerOrders(userId, query);
  },

  get(userId: number, orderId: string) {
    return getCustomerOrder(userId, orderId);
  }
};
