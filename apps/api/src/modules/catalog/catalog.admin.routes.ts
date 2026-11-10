import { Router } from "express";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

import {
  listAdminProductsController
} from "./catalog.admin.list.controller.js";

import {
  reactivateProductController
} from "./catalog.admin.reactivate.controller.js";

// ==========================================
// ADMINISTRACION DE PRODUCTOS
// ==========================================

export const adminProductsRouter = Router();

// ==========================================
// SEGURIDAD
// ==========================================

adminProductsRouter.use(
  requireAuth,
  requireRole("Administrador")
);

// ==========================================
// LISTAR PRODUCTOS
// GET /api/admin/products
// ==========================================

adminProductsRouter.get(
  "/",
  listAdminProductsController
);

// ==========================================
// REACTIVAR PRODUCTO
// PATCH /api/admin/products/:id/reactivate
// ==========================================

adminProductsRouter.patch(
  "/:id/reactivate",
  reactivateProductController
);
