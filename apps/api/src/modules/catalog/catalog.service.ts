import {
  findCatalogProducts
} from "./catalog.repository.js";

import type {
  CatalogQuery
} from "./catalog.schema.js";

export async function listCatalogProducts(
  filters: CatalogQuery
) {
  const result = await findCatalogProducts(filters);

  return {
    data: result.rows.map(row => ({
      idProducto: row.IDProducto,
      nombreProducto: row.NombreProducto,
      idCategoria: row.IDCategoria,
      nombreCategoria: row.NombreCategoria,
      idVariante: row.IDVariante,
      sku: row.SKU,
      precioActual: row.PrecioActual,
      cantidadFisica: row.CantidadFisica
    })),

    pagination: {
      page: filters.page,
      pageSize: filters.pageSize,
      total: result.total,
      totalPages: Math.ceil(
        result.total / filters.pageSize
      )
    }
  };
}
