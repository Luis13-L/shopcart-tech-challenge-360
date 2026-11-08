import sql from "mssql";

import { getDbPool } from "../../config/database.js";

import type {
  CreateProductInput
} from "./catalog.create.schema.js";

interface CreatedProductRow {
  IDProducto: number;
  IDVariante: number;
  Nombre: string;
  SKU: string;
  PrecioActual: number | string;
}

export async function insertProductWithImage(
  actorId: number,
  input: CreateProductInput,
  imageUrl: string
) {
  const pool = await getDbPool();
  const transaction = new sql.Transaction(pool);

  await transaction.begin();

  try {
    const created = await new sql.Request(transaction)
      .input("IDUsuarioActor", sql.Int, actorId)
      .input("IDCategoria", sql.Int, input.idCategoria)
      .input("Nombre", sql.NVarChar(200), input.nombre)
      .input(
        "Descripcion",
        sql.NVarChar(2000),
        input.descripcion ?? null
      )
      .input("SKU", sql.NVarChar(64), input.sku)
      .input(
        "PrecioActual",
        sql.Decimal(19, 2),
        Number(input.precioActual)
      )
      .execute<CreatedProductRow>(
        "dbo.SP_Catalogo_CrearProducto"
      );

    const product = created.recordset[0];

    if (!product) {
      throw new Error(
        "No se recibió el producto creado"
      );
    }

    await new sql.Request(transaction)
      .input("IDUsuarioActor", sql.Int, actorId)
      .input("IDProducto", sql.Int, product.IDProducto)
      .input("URLImagen", sql.NVarChar(1000), imageUrl)
      .input(
        "TextoAlternativo",
        sql.NVarChar(250),
        product.Nombre
      )
      .execute(
        "dbo.SP_Catalogo_RegistrarImagenProducto"
      );

    await transaction.commit();

    return {
      idProducto: product.IDProducto,
      idVariante: product.IDVariante,
      nombre: product.Nombre,
      sku: product.SKU,
      precioActual:
        Number(product.PrecioActual).toFixed(2),
      imagenUrl: imageUrl
    };

  } catch (error) {
    try {
      await transaction.rollback();
    } catch {
      // SQL Server pudo haber revertido ya la transacción.
    }

    throw error;
  }
}
