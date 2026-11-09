import type {
  RequestHandler
} from "express";

import {
  jwtVerify
} from "jose";

import {
  env
} from "../../config/env.js";

import {
  getCurrentPrincipal
} from "./auth.current.repository.js";

interface AuthPrincipal {
  id: number;
  role: string;
}

const jwtKey = Buffer.from(
  env.JWT_SECRET,
  "base64url"
);

// ==========================================
// VERIFICAR JWT Y PERMISOS VIGENTES
// ==========================================

export const requireAuth: RequestHandler = async (
  req,
  res,
  next
) => {
  const authorization =
    req.headers.authorization;

  const match = authorization?.match(
    /^Bearer\s+(\S+)$/i
  );

  if (!match) {
    res.status(401).json({
      status: 401,
      code: "UNAUTHORIZED",
      message: "Token de acceso requerido"
    });

    return;
  }

  // ========================================
  // 1. VALIDAR JWT CRIPTOGRAFICAMENTE
  // ========================================

  let payload;

  try {
    const verified = await jwtVerify(
      match[1]!,
      jwtKey,
      {
        issuer: "shopcart-api",
        audience: "shopcart-client",
        algorithms: ["HS256"]
      }
    );

    payload = verified.payload;

  } catch {
    res.status(401).json({
      status: 401,
      code: "INVALID_TOKEN",
      message: "Token invalido o expirado"
    });

    return;
  }

  const id = Number(payload.sub);

  if (
    !payload.sub ||
    !Number.isSafeInteger(id) ||
    id <= 0 ||
    typeof payload.role !== "string" ||
    typeof payload.sv !== "string" ||
    !/^[1-9]\d*$/.test(payload.sv)
  ) {
    res.status(401).json({
      status: 401,
      code: "INVALID_TOKEN",
      message: "Token invalido"
    });

    return;
  }

  // ========================================
  // 2. VALIDAR USUARIO EN SQL SERVER
  // ========================================

  try {
    const current = await getCurrentPrincipal(
      id
    );

    if (
      !current ||
      current.role !== payload.role ||
      current.securityVersion !== payload.sv
    ) {
      res.status(401).json({
        status: 401,
        code: "SESSION_CHANGED",
        message:
          "La sesion o los permisos cambiaron. " +
          "Inicia sesion nuevamente."
      });

      return;
    }

    // Solo confiar en los datos vigentes
    // obtenidos de SQL Server.

    res.locals.auth = {
      id: current.id,
      role: current.role
    } satisfies AuthPrincipal;

    next();

  } catch (error) {
    // Si SQL Server falla, no autorizar
    // la solicitud por defecto.
    // Dejar el error al middleware global.

    next(error);
  }
};

// ==========================================
// VERIFICAR ROL AUTORIZADO
// ==========================================

export function requireRole(
  ...allowedRoles: string[]
): RequestHandler {
  return (_req, res, next) => {
    const auth = res.locals.auth as
      | AuthPrincipal
      | undefined;

    if (!auth) {
      res.status(401).json({
        status: 401,
        code: "UNAUTHORIZED",
        message: "Autenticacion requerida"
      });

      return;
    }

    if (!allowedRoles.includes(auth.role)) {
      res.status(403).json({
        status: 403,
        code: "FORBIDDEN",
        message: "Permisos insuficientes"
      });

      return;
    }

    next();
  };
}
