import sql from "mssql";
import { getDbPool } from "../../config/database.js";

export async function reserveInventory(
  cartId: string,
  userId: number
): Promise<string> {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDCarrito", sql.BigInt, cartId)
    .input("IDUsuario", sql.Int, userId)
    .output("IDReserva", sql.BigInt)
    .execute("dbo.SP_Inventario_ReservarExistencia");

  const id: unknown = result.output.IDReserva;

  if (typeof id === "number" && Number.isSafeInteger(id) && id > 0) {
    return String(id);
  }

  if (typeof id === "string" && /^[1-9]\d*$/.test(id)) {
    return id;
  }

  if (typeof id === "bigint" && id > 0n) {
    return id.toString();
  }

  throw new Error("El SP no devolvió un IDReserva válido");
}
