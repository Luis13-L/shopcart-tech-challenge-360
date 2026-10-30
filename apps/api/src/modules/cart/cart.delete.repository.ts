import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

export async function deleteCartItem(
  cartId: string,
  userId: number,
  variantId: number
): Promise<void> {

  const pool = await getDbPool();

  await pool
    .request()
    .input("IDCarrito", sql.BigInt, cartId)
    .input("IDVariante", sql.Int, variantId)
    .input("IDUsuario", sql.Int, userId)
    .input("TokenInvitadoHash", sql.Binary, null)
    .execute(
      "dbo.SP_Carrito_EliminarProducto"
    );
}
