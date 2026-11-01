import { Router } from "express";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

import {
  salesReportController,
  categoriesReportController,
  topProductsReportController
} from "./reports.controller.js";

export const reportsRouter = Router();

// RF-08: reportes solo para Administrador
reportsRouter.use(
  requireAuth,
  requireRole("Administrador")
);

reportsRouter.get(
  "/sales",
  salesReportController
);

reportsRouter.get(
  "/categories",
  categoriesReportController
);

reportsRouter.get(
  "/top-products",
  topProductsReportController
);
