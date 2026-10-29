
import bcrypt from "bcryptjs";
import { SignJWT } from "jose";

import { env } from "../../config/env.js";
import { findUserByEmail } from "./auth.repository.js";
import type { LoginInput } from "./auth.schema.js";

const jwtKey = Buffer.from(
  env.JWT_SECRET,
  "base64url"
);

export async function login(
  input: LoginInput
) {
  const user = await findUserByEmail(input.correo);

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

  const accessToken = await new SignJWT({
    role: user.NombreRol
  })
    .setProtectedHeader({
      alg: "HS256",
      typ: "JWT"
    })
    .setSubject(String(user.IDUsuario))
    .setIssuer("shopcart-api")
    .setAudience("shopcart-client")
    .setIssuedAt()
    .setExpirationTime("15m")
    .sign(jwtKey);

  return {
    accessToken,
    tokenType: "Bearer",
    expiresIn: 900,
    user: {
      id: user.IDUsuario,
      correo: user.Correo,
      rol: user.NombreRol
    }
  };
}
