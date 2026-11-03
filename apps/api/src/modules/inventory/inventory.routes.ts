import { Router } from "express";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

import {
  registerMovementController,
  getStockController,
  getKardexController
} from "./inventory.controller.js";

export const inventoryRouter = Router();

inventoryRouter.use(
  requireAuth,
  requireRole("Operador", "Administrador")
);

inventoryRouter.post(
  "/movements",
  registerMovementController
);

inventoryRouter.get(
  "/variants/:id",
  getStockController
);

inventoryRouter.get(
  "/variants/:id/movements",
  getKardexController
);
