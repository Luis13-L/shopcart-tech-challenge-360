import { Router } from "express";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

import {
  listAdminUsersController
} from "./users.list.controller.js";

import {
  createAdminUserController
} from "./users.create.controller.js";

import {
  changeUserRoleController,
  changeUserStatusController
} from "./users.security.controller.js";

// ==========================================
// ADMINISTRACION DE USUARIOS
// ==========================================

export const adminUsersRouter = Router();

adminUsersRouter.use(
  requireAuth,
  requireRole("Administrador")
);

// ==========================================
// LISTAR USUARIOS
// ==========================================

adminUsersRouter.get(
  "/",
  listAdminUsersController
);

// ==========================================
// CREAR USUARIOS
// ==========================================

adminUsersRouter.post(
  "/",
  createAdminUserController
);

// ==========================================
// CAMBIAR ROL
// ==========================================

adminUsersRouter.patch(
  "/:id/role",
  changeUserRoleController
);

// ==========================================
// ACTIVAR O DESACTIVAR
// ==========================================

adminUsersRouter.patch(
  "/:id/status",
  changeUserStatusController
);
