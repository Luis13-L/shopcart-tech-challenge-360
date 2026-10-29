import express, {
  type ErrorRequestHandler
} from "express";

import cors from "cors";
import helmet from "helmet";
import { env } from "./config/env.js";
import { systemRouter } from "./modules/system/system.routes.js";
import { catalogRouter} from "./modules/catalog/catalog.routes.js";
import { authRouter } from "./modules/auth/auth.routes.js";

export function createApp() {
  const app = express();

  // Evitar divulgar informacion del framework
  app.disable("x-powered-by");

  // Cabeceras de seguridad
  app.use(helmet());

  // Permitir solicitudes del frontend
  app.use(cors({
    origin: env.CORS_ORIGIN
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

  app.use("/api/auth", authRouter);

  // Catalogo publico
app.use("/api/catalog/products", catalogRouter);
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
