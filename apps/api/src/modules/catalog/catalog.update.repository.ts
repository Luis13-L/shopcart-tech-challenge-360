
import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  UpdateProductInput
} from "./catalog.update.schema.js";

export interface UpdatedProductRow {
  IDProducto: number;
  IDCategoria: number;
  Nombre: string;
  Descripcion: string | null;
  Activo: boolean;
}

export async function updateProductInDatabase(
  productId: number,
  input: UpdateProductInput,
  actorId: number
): Promise<UpdatedProductRow> {

  const pool = await getDbPool();

  const changeDescription =
    Object.prototype.hasOwnProperty.call(
      input,
      "descripcion"
    );

  const result = await pool
    .request()
    .input("IDUsuarioActor", sql.Int, actorId)
    .input("IDProducto", sql.Int, productId)
    .input(
      "IDCategoria",
      sql.Int,
      input.idCategoria ?? null
    )
    .input(
      "Nombre",
      sql.NVarChar(200),
      input.nombre ?? null
    )
    .input(
      "Descripcion",
      sql.NVarChar(2000),
      input.descripcion ?? null
    )
    .input(
      "CambiarDescripcion",
      sql.Bit,
      changeDescription
    )
    .execute<UpdatedProductRow>(
      "dbo.SP_Catalogo_ActualizarProducto"
    );

  const product = result.recordset[0];

  if (!product) {
    throw new Error(
      "El procedimiento no devolvio el producto actualizado"
    );
  }

  return product;
}
