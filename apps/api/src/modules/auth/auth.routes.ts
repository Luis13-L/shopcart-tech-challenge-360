
import { Router } from "express";
import { rateLimit } from "express-rate-limit";

import { loginController } from "./auth.controller.js";
import { requireAuth, requireRole } from "./auth.middleware.js";
import { env } from "../../config/env.js";

export const authRouter = Router();

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: "draft-8",
  legacyHeaders: false,
  statusCode: 429,
  message: {
    status: 429,
    code: "TOO_MANY_REQUESTS",
    message: "Demasiados intentos. Intenta más tarde."
  }
});

// 1. LOGIN
authRouter.post(
  "/login",
  loginLimiter,
  loginController
);

// 2. VERIFICAR USUARIO AUTENTICADO
authRouter.get(
  "/me",
  requireAuth,
  (_req, res) => {
    res.status(200).json({
      user: res.locals.auth
    });
  }
);

// 3. VERIFICAR ROL ADMINISTRADOR
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
