import { Router } from "express";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

import {
  createAddressController,
  listAddressesController,
  getAddressController
} from "./addresses.controller.js";

export const addressesRouter = Router();

addressesRouter.use(
  requireAuth,
  requireRole("Cliente")
);

addressesRouter.post(
  "/",
  createAddressController
);

addressesRouter.get(
  "/",
  listAddressesController
);

addressesRouter.get(
  "/:id",
  getAddressController
);
