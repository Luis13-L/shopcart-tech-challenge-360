import express, {
  type ErrorRequestHandler
} from "express";

import cors from "cors";
import helmet from "helmet";
import { env } from "./config/env.js";
import { systemRouter } from "./modules/system/system.routes.js";
import { catalogRouter} from "./modules/catalog/catalog.routes.js";
import { authRouter } from "./modules/auth/auth.routes.js";
import { cartRouter } from "./modules/cart/cart.routes.js";
import { checkoutRouter } from "./modules/checkout/checkout.routes.js";
import { ordersRouter } from "./modules/orders/orders.routes.js";
import { couponsRouter } from "./modules/coupons/coupons.routes.js";
import { reportsRouter } from "./modules/reports/reports.routes.js";
import {  auditRouter } from "./modules/audit/audit.routes.js";
import {  variantPricesRouter } from "./modules/catalog/catalog.price.routes.js";
import {  categoriesRouter } from "./modules/categories/categories.routes.js";
import {  addressesRouter } from "./modules/addresses/addresses.routes.js";
import {  inventoryRouter } from "./modules/inventory/inventory.routes.js";
export function createApp() {
  const app = express();

  // Evitar divulgar informacion del framework
  app.disable("x-powered-by");

  // Cabeceras de seguridad
  app.use(helmet());

  // Permitir solicitudes del frontend
  app.use(cors({
  origin: env.CORS_ORIGIN,
  credentials: true
  }));

  // Procesamiento de JSON
  app.use(express.json({
    limit: "100kb"
  }));

  // Endpoint para verificar el servidor
  app.get("/api/health", (_req, res) => {
    res.status(200).json({
      status: "ok",
      service: "shopcart-api",
      timestamp: new Date().toISOString()
    });
  });
  // Registrar rutas de SqlServer
  app.use("/api/health", systemRouter);

  // Autenticacion y autorizacion
  app.use("/api/auth", authRouter);

  // Carrito de compras
  app.use("/api/cart", cartRouter);


  // Catalogo publico
app.use("/api/catalog/products", catalogRouter);

  // Checkout
  app.use("/api/checkout", checkoutRouter);
 
  // Ordenes
  app.use("/api/orders", ordersRouter);

  // Cupones
  app.use("/api/coupons", couponsRouter);

  // Reportes
  app.use("/api/reports", reportsRouter);

  // Auditoria
  app.use("/api/audit", auditRouter);

  // Precios de variantes
  app.use("/api/catalog/variants", variantPricesRouter);

  // Categorias
  app.use("/api/catalog/categories", categoriesRouter);

  // Direcciones
  app.use("/api/addresses", addressesRouter);

  // Inventario
  app.use("/api/inventory", inventoryRouter);
  // Rutas no encontradas
  app.use((_req, res) => {
    res.status(404).json({
      status: 404,
      code: "NOT_FOUND",
      message: "Recurso no encontrado"
    });
  });

  // Manejo centralizado de errores
  const errorHandler: ErrorRequestHandler = (
    error,
    _req,
    res,
    next
  ) => {
    if (res.headersSent) {
      next(error);
      return;
    }

    console.error("Error interno:", error);

    res.status(500).json({
      status: 500,
      code: "INTERNAL_SERVER_ERROR",
      message: "Error interno del servidor"
    });
  };

  app.use(errorHandler);

  return app;
}
