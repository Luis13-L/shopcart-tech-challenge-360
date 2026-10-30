
import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

export interface DeactivatedProductRow {
  IDProducto: number;
  Nombre: string;
  Activo: boolean;
  VariantesDesactivadas: number;
}

export async function deactivateProductInDatabase(
  productId: number,
  actorId: number
): Promise<DeactivatedProductRow> {

  const pool = await getDbPool();

  const result = await pool
    .request()
    .input("IDUsuarioActor", sql.Int, actorId)
    .input("IDProducto", sql.Int, productId)
    .execute<DeactivatedProductRow>(
      "dbo.SP_Catalogo_DesactivarProducto"
    );

  const product = result.recordset[0];

  if (!product) {
    throw new Error(
      "El procedimiento no devolvio el producto"
    );
  }

  return product;
}
