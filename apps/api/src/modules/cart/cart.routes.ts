import { Router } from "express";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

import {
  createCartController
} from "./cart.controller.js";

import {
  getCartController
} from "./cart.read.controller.js";

import {
  saveCartItemController
} from "./cart.items.controller.js";

import {
  deleteCartItemController
} from "./cart.delete.controller.js";

export const cartRouter = Router();

// Crear u obtener carrito
cartRouter.post(
  "/",
  requireAuth,
  requireRole("Cliente"),
  createCartController
);

// Consultar contenido
cartRouter.get(
  "/:id",
  requireAuth,
  requireRole("Cliente"),
  getCartController
);

// Agregar o actualizar cantidades
cartRouter.put(
  "/items",
  requireAuth,
  requireRole("Cliente"),
  saveCartItemController
);

// Eliminar una variante
cartRouter.delete(
  "/items/:id",
  requireAuth,
  requireRole("Cliente"),
  deleteCartItemController
);
