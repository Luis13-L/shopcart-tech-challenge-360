
import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

export async function createOrGetCart(
  userId: number
): Promise<string> {

  const pool = await getDbPool();

  const result = await pool
    .request()
    .input(
      "IDUsuario",
      sql.Int,
      userId
    )
    .input(
  "TokenInvitadoHash",
  sql.Binary,
  null
)
    .output(
      "IDCarrito",
      sql.BigInt
    )
    .execute("dbo.SP_Carrito_Crear");

  const rawId: unknown = result.output.IDCarrito;

  // BIGINT debe manejarse sin perder precision
  if (typeof rawId === "number") {
    if (
      !Number.isSafeInteger(rawId) ||
      rawId <= 0
    ) {
      throw new Error("ID de carrito invalido");
    }

    return String(rawId);
  }

  if (
    typeof rawId === "string" &&
    /^[1-9]\d*$/.test(rawId)
  ) {
    return rawId;
  }

  if (typeof rawId === "bigint" && rawId > 0n) {
    return rawId.toString();
  }

  throw new Error(
    "El procedimiento no devolvio IDCarrito"
  );
}
