
import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  CreateProductInput
} from "./catalog.create.schema.js";

interface CreatedProductRow {
  IDProducto: number;
  IDVariante: number;
  Nombre: string;
  SKU: string;
  PrecioActual: number;
}

export async function insertCatalogProduct(
  input: CreateProductInput,
  actorId: number
): Promise<CreatedProductRow> {

  const pool = await getDbPool();

  const result = await pool
    .request()
    .input("IDUsuarioActor", sql.Int, actorId)
    .input(
      "IDCategoria",
      sql.Int,
      input.idCategoria
    )
    .input(
      "Nombre",
      sql.NVarChar(200),
      input.nombre
    )
    .input(
      "Descripcion",
      sql.NVarChar(2000),
      input.descripcion ?? null
    )
    .input(
      "SKU",
      sql.NVarChar(64),
      input.sku
    )
    .input(
      "PrecioActual",
      sql.Decimal(19, 2),
      Number(input.precioActual)
    )
    .execute<CreatedProductRow>(
      "dbo.SP_Catalogo_CrearProducto"
    );

  const product = result.recordset[0];

  if (!product) {
    throw new Error(
      "El procedimiento no devolvio el producto creado"
    );
  }

  return product;
}
