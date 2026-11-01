
import { Router } from "express";

import {
  requireAuth
} from "../auth/auth.middleware.js";

import {
  changeOrderStatusController
} from "./orders.status.controller.js";

import {
  cancelOrderController
} from "./orders.cancel.controller.js";

import {
  returnOrderController
} from "./orders.return.controller.js";

export const ordersRouter = Router();

// Operador o Administrador:
// avanzar el estado de un pedido.
ordersRouter.patch(
  "/:id/status",
  requireAuth,
  changeOrderStatusController
);

// Cliente propietario, Operador o Administrador:
// cancelar pedidos no despachados.
ordersRouter.post(
  "/:id/cancel",
  requireAuth,
  cancelOrderController
);

// Registrar devolucion
ordersRouter.post(
  "/:id/returns",
  requireAuth,
  returnOrderController
);
