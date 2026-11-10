import { Router } from "express";
import { requireAuth, requireRole } from "../auth/auth.middleware.js";
import {
  listAdminVariantsController,
  createAdminVariantController,
  changeAdminVariantStatusController
} from "./catalog.admin.variants.controller.js";

export const adminVariantsRouter = Router();

adminVariantsRouter.use(
  requireAuth,
  requireRole("Administrador")
);

adminVariantsRouter.get("/", listAdminVariantsController);
adminVariantsRouter.post("/", createAdminVariantController);
adminVariantsRouter.patch("/:id/status", changeAdminVariantStatusController);
