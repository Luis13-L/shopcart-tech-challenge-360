
import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

export async function saveCartItem(
  cartId: string,
  userId: number,
  variantId: number,
  quantity: number
): Promise<void> {

  const pool = await getDbPool();

  await pool
    .request()
    .input(
      "IDCarrito",
      sql.BigInt,
      cartId
    )
    .input(
      "IDVariante",
      sql.Int,
      variantId
    )
    .input(
      "Cantidad",
      sql.Int,
      quantity
    )
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
    .execute(
      "dbo.SP_Carrito_GuardarDetalle"
    );
}
