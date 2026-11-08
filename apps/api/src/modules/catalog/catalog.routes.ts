
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
  deactivateProductController
} from "./catalog.deactivate.controller.js";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

import {
  uploadProductImage
} from "./catalog.image.upload.js";

import {
  createProductWithImageController
} from "./catalog.image.controller.js";

export const catalogRouter = Router();

// GET - Listar productos
catalogRouter.get(
  "/",
  getCatalogProducts
);

// POST - Crear producto
catalogRouter.post(
  "/",
  requireAuth,
  requireRole("Administrador"),
  createProductController
);

//imagenes
catalogRouter.post(
  "/with-image",
  requireAuth,
  requireRole("Administrador"),
  uploadProductImage,
  createProductWithImageController
);


// PATCH - Actualizar producto
catalogRouter.patch(
  "/:id",
  requireAuth,
  requireRole("Administrador"),
  updateProductController
);

// PATCH - Desactivar producto
catalogRouter.patch(
  "/:id/status",
  requireAuth,
  requireRole("Administrador"),
  deactivateProductController
);
