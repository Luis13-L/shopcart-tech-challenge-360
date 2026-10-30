
import { Router } from "express";

import {
  getCatalogProducts
} from "./catalog.controller.js";

import {
  createProductController
} from "./catalog.create.controller.js";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

export const catalogRouter = Router();

// Listado publico
catalogRouter.get(
  "/",
  getCatalogProducts
);

// Creacion administrativa
catalogRouter.post(
  "/",
  requireAuth,
  requireRole("Administrador"),
  createProductController
);
