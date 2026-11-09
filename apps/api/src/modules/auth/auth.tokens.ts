import { SignJWT } from "jose";

import {
  env
} from "../../config/env.js";

import {
  getCurrentPrincipal
} from "./auth.current.repository.js";

const jwtKey = Buffer.from(
  env.JWT_SECRET,
  "base64url"
);

export const ACCESS_TOKEN_SECONDS = 900;

// ==========================================
// GENERAR JWT CON VERSION DE SEGURIDAD
// ==========================================

export async function createAccessToken(
  userId: number,
  role: string
): Promise<string> {
  const current = await getCurrentPrincipal(
    userId
  );

  if (
    !current ||
    current.role !== role
  ) {
    throw new Error(
      "El usuario o sus permisos cambiaron"
    );
  }

  return new SignJWT({
    role: current.role,
    sv: current.securityVersion
  })
    .setProtectedHeader({
      alg: "HS256",
      typ: "JWT"
    })
    .setSubject(String(current.id))
    .setIssuer("shopcart-api")
    .setAudience("shopcart-client")
    .setIssuedAt()
    .setExpirationTime("15m")
    .sign(jwtKey);
}
