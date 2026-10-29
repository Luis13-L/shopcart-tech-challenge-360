
import type { RequestHandler } from "express";
import { jwtVerify } from "jose";

import { env } from "../../config/env.js";

interface AuthPrincipal {
  id: number;
  role: string;
}

const jwtKey = Buffer.from(
  env.JWT_SECRET,
  "base64url"
);

// Verificar autenticacion
export const requireAuth: RequestHandler = async (
  req,
  res,
  next
) => {
  const authorization = req.headers.authorization;

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

  try {
    const { payload } = await jwtVerify(
      match[1]!,
      jwtKey,
      {
        issuer: "shopcart-api",
        audience: "shopcart-client",
        algorithms: ["HS256"]
      }
    );

    const id = Number(payload.sub);

    if (
      !payload.sub ||
      !Number.isSafeInteger(id) ||
      id <= 0 ||
      typeof payload.role !== "string" ||
      payload.role.length === 0
    ) {
      res.status(401).json({
        status: 401,
        code: "INVALID_TOKEN",
        message: "Token invalido"
      });
      return;
    }

    res.locals.auth = {
      id,
      role: payload.role
    } satisfies AuthPrincipal;

    next();

  } catch {
    res.status(401).json({
      status: 401,
      code: "INVALID_TOKEN",
      message: "Token invalido o expirado"
    });
  }
};

// Verificar autorizacion por rol
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
