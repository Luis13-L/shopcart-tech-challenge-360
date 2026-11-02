import { Router } from "express";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

import {
  listPublicCategoriesController,
  listAdminCategoriesController,
  createCategoryController,
  updateCategoryController,
  changeCategoryStatusController
} from "./categories.controller.js";

export const categoriesRouter = Router();

// Consulta publica: solo categorias activas.
categoriesRouter.get(
  "/",
  listPublicCategoriesController
);

// Consulta administrativa: incluye inactivas.
categoriesRouter.get(
  "/admin",
  requireAuth,
  requireRole("Administrador"),
  listAdminCategoriesController
);

// Crear categoria.
categoriesRouter.post(
  "/",
  requireAuth,
  requireRole("Administrador"),
  createCategoryController
);

// Actualizar categoria.
categoriesRouter.patch(
  "/:id",
  requireAuth,
  requireRole("Administrador"),
  updateCategoryController
);

// Activar o desactivar categoria.
categoriesRouter.patch(
  "/:id/status",
  requireAuth,
  requireRole("Administrador"),
  changeCategoryStatusController
);
