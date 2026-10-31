
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

export const checkoutRouter = Router();

// Iniciar reserva de 15 minutos
checkoutRouter.post(
  "/reservations",
  requireAuth,
  requireRole("Cliente"),
  reserveInventoryController
);

// Confirmar compra
checkoutRouter.post(
  "/confirm",
  requireAuth,
  requireRole("Cliente"),
  confirmCheckoutController
);
