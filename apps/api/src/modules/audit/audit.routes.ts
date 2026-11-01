import { Router } from "express";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

import {
  listAuditController
} from "./audit.controller.js";

export const auditRouter = Router();

auditRouter.use(
  requireAuth,
  requireRole("Administrador")
);

auditRouter.get(
  "/",
  listAuditController
);
