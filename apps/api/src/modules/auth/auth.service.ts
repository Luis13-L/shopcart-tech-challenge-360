import bcrypt from "bcryptjs";

import {
  findUserByEmail
} from "./auth.repository.js";

import type {
  LoginInput
} from "./auth.schema.js";

import {
  createAccessToken,
  ACCESS_TOKEN_SECONDS
} from "./auth.tokens.js";

import {
  createRefreshSession
} from "./auth.refresh.service.js";

export async function login(
  input: LoginInput
) {
  const user = await findUserByEmail(
    input.correo
  );

  if (!user) {
    return null;
  }

  const passwordIsValid = await bcrypt.compare(
    input.password,
    user.PasswordHash
  );

  if (!passwordIsValid) {
    return null;
  }

  const accessToken = await createAccessToken(
    user.IDUsuario,
    user.NombreRol
  );

  const refreshToken = await createRefreshSession(
    user.IDUsuario
  );

  return {
    accessToken,
    refreshToken,
    tokenType: "Bearer" as const,
    expiresIn: ACCESS_TOKEN_SECONDS,

    user: {
      id: user.IDUsuario,
      correo: user.Correo,
      rol: user.NombreRol
    }
  };
}
