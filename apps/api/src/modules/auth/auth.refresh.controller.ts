import type {
  Request,
  Response,
  NextFunction
} from "express";

import {
  env
} from "../../config/env.js";

import {
  renewSession,
  closeRefreshSession
} from "./auth.refresh.service.js";

const COOKIE_NAME = "shopcart_refresh";

const COOKIE_MAX_AGE =
  7 * 24 * 60 * 60 * 1000;

const cookieOptions = {
  httpOnly: true,
  secure: env.NODE_ENV === "production",
  sameSite: "strict" as const,
  path: "/api/auth"
};

// ==========================================
// UTILIDADES DE COOKIE
// ==========================================

export function setRefreshCookie(
  res: Response,
  refreshToken: string
): void {
  res.cookie(
    COOKIE_NAME,
    refreshToken,
    {
      ...cookieOptions,
      maxAge: COOKIE_MAX_AGE
    }
  );
}

export function clearRefreshCookie(
  res: Response
): void {
  res.clearCookie(
    COOKIE_NAME,
    cookieOptions
  );
}

function readRefreshCookie(
  req: Request
): string | null {
  const header = req.headers.cookie;

  if (!header) {
    return null;
  }

  for (const item of header.split(";")) {
    const separator = item.indexOf("=");

    if (separator < 0) {
      continue;
    }

    const name = item
      .slice(0, separator)
      .trim();

    if (name === COOKIE_NAME) {
      return item
        .slice(separator + 1)
        .trim();
    }
  }

  return null;
}

// Verificar Origin para solicitudes que
// utilizan cookies de autenticacion.
function hasInvalidOrigin(
  req: Request
): boolean {
  const origin = req.get("origin");

  return (
    origin !== undefined &&
    origin !== env.CORS_ORIGIN
  );
}

// ==========================================
// POST /api/auth/refresh
// ==========================================

export async function refreshController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  if (hasInvalidOrigin(req)) {
    res.status(403).json({
      code: "FORBIDDEN_ORIGIN",
      message: "Origen no permitido"
    });
    return;
  }

  const currentToken = readRefreshCookie(req);

  if (!currentToken) {
    res.status(401).json({
      code: "INVALID_REFRESH_TOKEN",
      message: "Sesion no disponible"
    });
    return;
  }

  try {
    const result = await renewSession(
      currentToken
    );

    if (!result) {
      clearRefreshCookie(res);

      res.status(401).json({
        code: "INVALID_REFRESH_TOKEN",
        message: "Sesion expirada o revocada"
      });
      return;
    }

    setRefreshCookie(
      res,
      result.refreshToken
    );

    // Nunca devolver refreshToken en JSON.
    const { refreshToken: _hidden, ...data } =
      result;

    res.status(200).json(data);

  } catch (error) {
    next(error);
  }
}

// ==========================================
// POST /api/auth/logout
// ==========================================

export async function logoutController(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  if (hasInvalidOrigin(req)) {
    res.status(403).json({
      code: "FORBIDDEN_ORIGIN",
      message: "Origen no permitido"
    });
    return;
  }

  const refreshToken = readRefreshCookie(req);

  try {
    if (refreshToken) {
      await closeRefreshSession(
        refreshToken
      );
    }

    clearRefreshCookie(res);

    res.status(204).send();

  } catch (error) {
    next(error);
  }
}
