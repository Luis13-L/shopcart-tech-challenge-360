import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  ListAdminProductsInput
} from "./catalog.admin.list.schema.js";

// ==========================================
// CONTRATOS SQL SERVER
// ==========================================

type SqlBigInt = string | number | bigint;

interface TotalRow {
  Total: SqlBigInt;
}

interface AdminProductRow {
  IDProducto: number;
  NombreProducto: string;
  Descripcion: string | null;
  Activo: boolean | number;
  FechaCreacion: Date | string;

  IDCategoria: number;
  NombreCategoria: string;
  CategoriaActiva: boolean | number;

  IDVarianteReferencia: number | null;
  SKUReferencia: string | null;
  PrecioReferencia: string | null;

  VarianteReferenciaActiva:
    | boolean
    | number
    | null;

  CantidadFisicaReferencia: number;
  TotalVariantes: number;
  VariantesActivas: number;

  URLImagen: string | null;
  TextoAlternativo: string | null;
}

// ==========================================
// CONVERSIONES SEGURAS
// ==========================================

function toSafeCount(
  value: SqlBigInt
): number {
  const count = Number(value);

  if (
    !Number.isSafeInteger(count) ||
    count < 0
  ) {
    throw new Error(
      "Contador de productos fuera de rango"
    );
  }

  return count;
}

function toBoolean(
  value: boolean | number
): boolean {
  return value === true || value === 1;
}

function toIsoDate(
  value: Date | string
): string {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    throw new Error(
      "Fecha de producto invalida"
    );
  }

  return date.toISOString();
}

// ==========================================
// MAPEAR PRODUCTO
// ==========================================

function mapAdminProduct(
  row: AdminProductRow
) {
  return {
    idProducto: row.IDProducto,
    nombreProducto: row.NombreProducto,

    descripcion: row.Descripcion,

    activo: toBoolean(row.Activo),

    fechaCreacion: toIsoDate(
      row.FechaCreacion
    ),

    idCategoria: row.IDCategoria,
    nombreCategoria: row.NombreCategoria,

    categoriaActiva: toBoolean(
      row.CategoriaActiva
    ),

    idVarianteReferencia:
      row.IDVarianteReferencia,

    skuReferencia:
      row.SKUReferencia,

    precioReferencia:
      row.PrecioReferencia,

    varianteReferenciaActiva:
      row.VarianteReferenciaActiva === null
        ? null
        : toBoolean(
            row.VarianteReferenciaActiva
          ),

    cantidadFisicaReferencia:
      row.CantidadFisicaReferencia,

    totalVariantes:
      row.TotalVariantes,

    variantesActivas:
      row.VariantesActivas,

    imagenUrl:
      row.URLImagen,

    imagenAlt:
      row.TextoAlternativo
  };
}

// ==========================================
// LISTAR PRODUCTOS ADMINISTRATIVOS
// ==========================================

export async function listAdminProducts(
  actorId: number,
  input: ListAdminProductsInput
) {
  const pool = await getDbPool();

  const result = await pool.request()

    .input(
      "IDUsuarioActor",
      sql.Int,
      actorId
    )

    .input(
      "Pagina",
      sql.Int,
      input.pagina
    )

    .input(
      "TamanoPagina",
      sql.Int,
      input.tamanoPagina
    )

    .input(
      "Busqueda",
      sql.NVarChar(120),
      input.busqueda
    )

    .input(
      "Activo",
      sql.Bit,
      input.activo
    )

    .input(
      "IDCategoria",
      sql.Int,
      input.idCategoria
    )

    .execute(
      "dbo.SP_Catalogo_ListarProductosAdmin"
    );

  // ========================================
  // RESULTSET 0: TOTAL
  // RESULTSET 1: PRODUCTOS
  // ========================================

  const recordsets =
    result.recordsets as unknown as [
      TotalRow[],
      AdminProductRow[]
    ];

  if (
    !Array.isArray(recordsets) ||
    !Array.isArray(recordsets[0]) ||
    !Array.isArray(recordsets[1])
  ) {
    throw new Error(
      "SQL Server no devolvio los dos resultados esperados"
    );
  }

  const totalRow = recordsets[0][0];

  if (!totalRow) {
    throw new Error(
      "No se recibio el total de productos"
    );
  }

  const totalRegistros = toSafeCount(
    totalRow.Total
  );

  const rows = recordsets[1];

  return {
    items: rows.map(mapAdminProduct),

    pagination: {
      pagina: input.pagina,
      tamanoPagina: input.tamanoPagina,
      totalRegistros,
      totalPaginas: Math.ceil(
        totalRegistros / input.tamanoPagina
      )
    }
  };
}
