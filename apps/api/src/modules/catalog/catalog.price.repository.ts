import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  UpdateVariantPriceInput
} from "./catalog.price.schema.js";

interface PriceRow {
  IDVariante: number;
  IDProducto: number;
  SKU: string;
  PrecioAnterior: number | string;
  PrecioActual: number | string;
  Actualizado: boolean | number;
  FechaCambio: Date | string | null;
}

export async function updateVariantPriceInDatabase(
  variantId: number,
  actorId: number,
  input: UpdateVariantPriceInput
): Promise<PriceRow> {

  const pool = await getDbPool();

  const result = await pool.request()
    .input(
      "IDUsuarioActor",
      sql.Int,
      actorId
    )
    .input(
      "IDVariante",
      sql.Int,
      variantId
    )
    .input(
      "PrecioNuevo",
      sql.Decimal(19, 2),
      Number(input.precioNuevo)
    )
    .input(
      "Motivo",
      sql.NVarChar(300),
      input.motivo
    )
    .execute<PriceRow>(
      "dbo.SP_Catalogo_ActualizarPrecioVariante"
    );

  const row = result.recordset[0];

  if (!row) {
    throw new Error(
      "El procedimiento no devolvio la variante"
    );
  }

  return row;
}
