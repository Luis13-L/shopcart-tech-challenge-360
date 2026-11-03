import { Router } from "express";

import {
  requireAuth,
  requireRole
} from "../auth/auth.middleware.js";

import {
  createCouponController,
  listCouponsController,
  getCouponController,
  updateCouponController,
  changeCouponStatusController,
  listCouponUsesController,
  assignCouponCategoryController
} from "./coupons.controller.js";

export const couponsRouter = Router();

// Todas las rutas requieren autenticacion
// y rol Administrador.
couponsRouter.use(
  requireAuth,
  requireRole("Administrador")
);

// Crear cupon
couponsRouter.post(
  "/",
  createCouponController
);

// Listar cupones
couponsRouter.get(
  "/",
  listCouponsController
);

// Consultar usos de un cupon
couponsRouter.get(
  "/:id/uses",
  listCouponUsesController
);

// Obtener cupon por ID
couponsRouter.get(
  "/:id",
  getCouponController
);

// Actualizar cupon
couponsRouter.put(
  "/:id",
  updateCouponController
);

// Activar / desactivar cupon
couponsRouter.patch(
  "/:id/status",
  changeCouponStatusController
);

// Asignar o quitar la categoria de un cupon.
couponsRouter.patch(
  "/:id/category",
  assignCouponCategoryController
);
