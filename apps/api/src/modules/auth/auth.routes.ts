import { Router } from "express";
import { rateLimit } from "express-rate-limit";

import {
  loginController
} from "./auth.controller.js";

import {
  registerController
} from "./auth.register.controller.js";

import {
  refreshController,
  logoutController
} from "./auth.refresh.controller.js";

import {
  requireAuth,
  requireRole
} from "./auth.middleware.js";

import {
  env
} from "../../config/env.js";

export const authRouter = Router();

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: "draft-8",
  legacyHeaders: false,
  statusCode: 429,
  message: {
    code: "TOO_MANY_REQUESTS",
    message: "Demasiados intentos"
  }
});

const registerLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 5,
  standardHeaders: "draft-8",
  legacyHeaders: false,
  statusCode: 429,
  message: {
    code: "TOO_MANY_REQUESTS",
    message: "Demasiados registros"
  }
});

const refreshLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 30,
  standardHeaders: "draft-8",
  legacyHeaders: false,
  statusCode: 429,
  message: {
    code: "TOO_MANY_REQUESTS",
    message: "Demasiadas renovaciones"
  }
});

// Registro publico
authRouter.post(
  "/register",
  registerLimiter,
  registerController
);

// Login
authRouter.post(
  "/login",
  loginLimiter,
  loginController
);

// Renovacion de sesion
authRouter.post(
  "/refresh",
  refreshLimiter,
  refreshController
);

// Cierre de sesion
authRouter.post(
  "/logout",
  logoutController
);

// Usuario autenticado
authRouter.get(
  "/me",
  requireAuth,
  (_req, res) => {
    res.status(200).json({
      user: res.locals.auth
    });
  }
);

// Verificacion administrativa en desarrollo
if (env.NODE_ENV === "development") {
  authRouter.get(
    "/admin-check",
    requireAuth,
    requireRole("Administrador"),
    (_req, res) => {
      res.status(200).json({
        authorized: true,
        role: res.locals.auth.role
      });
    }
  );
}
