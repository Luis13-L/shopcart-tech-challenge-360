import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

// ==========================================
// CONTRATO SQL SERVER
// ==========================================

interface ReactivatedProductRow {
  IDProducto: number;
  Nombre: string;
  Activo: boolean | number;
  VariantesReactivadas: number;
  Reutilizado: boolean | number;
}

// ==========================================
// REACTIVAR PRODUCTO EN SQL SERVER
// ==========================================

export async function reactivateProductInDatabase(
  productId: number,
  actorId: number
): Promise<ReactivatedProductRow> {

  const pool = await getDbPool();

  const result = await pool.request()

    .input(
      "IDUsuarioActor",
      sql.Int,
      actorId
    )

    .input(
      "IDProducto",
      sql.Int,
      productId
    )

    .execute<ReactivatedProductRow>(
      "dbo.SP_Catalogo_ReactivarProducto"
    );

  const product = result.recordset[0];

  if (!product) {
    throw new Error(
      "El procedimiento no devolvio el producto"
    );
  }

  return product;
}
