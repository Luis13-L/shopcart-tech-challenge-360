import { Router } from "express";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

import {
  reserveInventoryController
} from "./checkout.reservation.controller.js";

import {
  confirmCheckoutController
} from "./checkout.confirm.controller.js";

import {
  quoteCheckoutController
} from "./checkout.quote.controller.js";

export const checkoutRouter = Router();

// ==========================================
// RESERVAR INVENTARIO
// ==========================================

checkoutRouter.post(
  "/reservations",
  requireAuth,
  requireRole("Cliente"),
  reserveInventoryController
);

// ==========================================
// COTIZAR CUPON SIN CONSUMIRLO
// PASO 75B.3
// ==========================================

checkoutRouter.post(
  "/quote",
  requireAuth,
  requireRole("Cliente"),
  quoteCheckoutController
);

// ==========================================
// CONFIRMAR COMPRA
// ==========================================

checkoutRouter.post(
  "/confirm",
  requireAuth,
  requireRole("Cliente"),
  confirmCheckoutController
);
