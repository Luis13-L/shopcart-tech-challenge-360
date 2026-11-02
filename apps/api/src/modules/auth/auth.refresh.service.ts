import {
  randomBytes,
  createHash
} from "node:crypto";

import {
  createAccessToken,
  ACCESS_TOKEN_SECONDS
} from "./auth.tokens.js";

import {
  saveRefreshToken,
  rotateRefreshTokenInDatabase,
  revokeRefreshTokenInDatabase
} from "./auth.refresh.repository.js";

const refreshTokenPattern =
  /^[A-Za-z0-9_-]{43}$/;

function generateRefreshToken(): string {
  return randomBytes(32).toString("base64url");
}

function hashRefreshToken(
  token: string
): Buffer {
  return createHash("sha256")
    .update(token, "utf8")
    .digest();
}

function isValidRefreshToken(
  token: string
): boolean {
  return refreshTokenPattern.test(token);
}

// ==========================================
// CREAR SESION DESPUES DEL LOGIN
// ==========================================

export async function createRefreshSession(
  userId: number
): Promise<string> {
  const refreshToken = generateRefreshToken();

  await saveRefreshToken(
    userId,
    hashRefreshToken(refreshToken)
  );

  return refreshToken;
}

// ==========================================
// ROTAR REFRESH TOKEN
// ==========================================

export async function renewSession(
  currentToken: string
) {
  if (!isValidRefreshToken(currentToken)) {
    return null;
  }

  const newRefreshToken =
    generateRefreshToken();

  const row = await rotateRefreshTokenInDatabase(
    hashRefreshToken(currentToken),
    hashRefreshToken(newRefreshToken)
  );

  // Incluye INVALIDO, EXPIRADO,
  // INACTIVO y REUTILIZADO.
  if (
    row.Codigo !== "ROTADO" ||
    row.IDUsuario == null ||
    row.Correo == null ||
    row.NombreRol == null
  ) {
    return null;
  }

  const accessToken = await createAccessToken(
    row.IDUsuario,
    row.NombreRol
  );

  return {
    refreshToken: newRefreshToken,
    accessToken,
    tokenType: "Bearer" as const,
    expiresIn: ACCESS_TOKEN_SECONDS,
    user: {
      id: row.IDUsuario,
      correo: row.Correo,
      rol: row.NombreRol
    }
  };
}

// ==========================================
// CERRAR SESION
// ==========================================

export async function closeRefreshSession(
  refreshToken: string
): Promise<void> {
  if (!isValidRefreshToken(refreshToken)) {
    return;
  }

  await revokeRefreshTokenInDatabase(
    hashRefreshToken(refreshToken)
  );
}
