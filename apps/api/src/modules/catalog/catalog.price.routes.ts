import { Router } from "express";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

import {
  updateVariantPriceController
} from "./catalog.price.controller.js";

export const variantPricesRouter = Router();

variantPricesRouter.patch(
  "/:id/price",
  requireAuth,
  requireRole("Administrador"),
  updateVariantPriceController
);
