
import sql from "mssql";

import { getDbPool } from "../../config/database.js";
import type { CatalogQuery } from "./catalog.schema.js";

export interface CatalogProductRow {
  IDProducto: number;
  NombreProducto: string;
  IDCategoria: number;
  NombreCategoria: string;
  IDVariante: number;
  SKU: string;
  PrecioActual: string;
  CantidadFisica: number;
}

export interface CatalogResult {
  rows: CatalogProductRow[];
  total: number;
}

export async function findCatalogProducts(
  filters: CatalogQuery
): Promise<CatalogResult> {

  const pool = await getDbPool();

  const request = pool.request()
    .input(
      "Busqueda",
      sql.NVarChar(120),
      filters.search || null
    )
    .input(
      "IDCategoria",
      sql.Int,
      filters.categoryId ?? null
    )
    .input(
      "PrecioMin",
      sql.Decimal(19, 2),
      filters.minPrice ?? null
    )
    .input(
      "PrecioMax",
      sql.Decimal(19, 2),
      filters.maxPrice ?? null
    )
    .input(
      "SoloDisponibles",
      sql.Bit,
      filters.available
    )
    .input(
      "Orden",
      sql.VarChar(20),
      filters.sort
    )
    .input(
      "Pagina",
      sql.Int,
      filters.page
    )
    .input(
      "TamPagina",
      sql.Int,
      filters.pageSize
    );

  const result = await request.execute(
    "dbo.SP_Catalogo_ListarProductos"
  );

  
const recordsets = result.recordsets;

// Verificar que el SP devolvio conjuntos de resultados
if (
  !Array.isArray(recordsets) ||
  !recordsets[0] ||
  !recordsets[1]
) {
  throw new Error(
    "SP_Catalogo_ListarProductos debe devolver dos conjuntos de resultados"
  );
}

// Primer resultado: total de registros
const totalRow = recordsets[0][0] as
  | { Total: number }
  | undefined;

if (
  !totalRow ||
  !Number.isSafeInteger(totalRow.Total) ||
  totalRow.Total < 0
) {
  throw new Error(
    "El procedimiento no devolvio un total valido"
  );
}

// Segundo resultado: productos de la pagina
const rows = recordsets[1] as CatalogProductRow[];

return {
  rows,
  total: totalRow.Total
};

}
