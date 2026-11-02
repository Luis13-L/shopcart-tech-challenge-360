import { SignJWT } from "jose";
import { env } from "../../config/env.js";

const jwtKey = Buffer.from(
  env.JWT_SECRET,
  "base64url"
);

export const ACCESS_TOKEN_SECONDS = 900;

export async function createAccessToken(
  userId: number,
  role: string
): Promise<string> {
  return new SignJWT({ role })
    .setProtectedHeader({
      alg: "HS256",
      typ: "JWT"
    })
    .setSubject(String(userId))
    .setIssuer("shopcart-api")
    .setAudience("shopcart-client")
    .setIssuedAt()
    .setExpirationTime("15m")
    .sign(jwtKey);
}
