
import { Router } from "express";

import {
  getCatalogProducts
} from "./catalog.controller.js";

import {
  createProductController
} from "./catalog.create.controller.js";

import {
  updateProductController
} from "./catalog.update.controller.js";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

export const catalogRouter = Router();

// ========================================
// GET - Listado publico de productos
// ========================================
catalogRouter.get(
  "/",
  getCatalogProducts
);

// ========================================
// POST - Crear producto
// Solo Administrador
// ========================================
catalogRouter.post(
  "/",
  requireAuth,
  requireRole("Administrador"),
  createProductController
);

// ========================================
// PATCH - Actualizar producto
// Solo Administrador
// ========================================
catalogRouter.patch(
  "/:id",
  requireAuth,
  requireRole("Administrador"),
  updateProductController
);
