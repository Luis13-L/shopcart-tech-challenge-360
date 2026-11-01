import type {
  SalesReportInput,
  DateRangeInput,
  OrdersReportInput
} from "./reports.schema.js";

import {
  getSalesReport,
  getCategoriesReport,
  getTopProductsReport,
  getOrdersReport
} from "./reports.repository.js";

export const reportsService = {

  sales(
    userId: number,
    input: SalesReportInput
  ) {
    return getSalesReport(userId, input);
  },

  categories(
    userId: number,
    input: DateRangeInput
  ) {
    return getCategoriesReport(userId, input);
  },

  topProducts(
    userId: number,
    input: DateRangeInput
  ) {
    return getTopProductsReport(userId, input);
  },

  orders(
    userId: number,
    input: OrdersReportInput
  ) {
    return getOrdersReport(userId, input);
  }
};
