import sql from "mssql";
import { getDbPool } from "../../config/database.js";
import { variantAttributesSchema } from "./catalog.admin.variants.schema.js";
import type {
  ListAdminVariantsInput,
  CreateAdminVariantInput
} from "./catalog.admin.variants.schema.js";

type SqlCount = number | string | bigint;

interface TotalRow {
  Total: SqlCount;
}

interface AdminVariantRow {
  IDVariante: number;
  IDProducto: number;
  SKU: string;
  PrecioActual: string;
  Activa: boolean | number;
  FechaCreacion: Date | string;
  CantidadFisica: number;
  AtributosJson: string | null;
}

interface CreatedVariantRow {
  IDVariante: number;
  IDProducto: number;
  SKU: string;
  PrecioActual: string;
  Activa: boolean | number;
  CantidadFisica: number;
}

interface VariantStatusRow {
  IDVariante: number;
  IDProducto: number;
  SKU: string;
  Activa: boolean | number;
  Actualizado: boolean | number;
}

function toBoolean(value: boolean | number): boolean {
  return value === true || value === 1;
}

function toSafeCount(value: SqlCount): number {
  const result = Number(value);
  if (!Number.isSafeInteger(result) || result < 0) {
    throw new Error("Total de variantes fuera de rango");
  }
  return result;
}

function mapVariant(row: AdminVariantRow) {
  const date = new Date(row.FechaCreacion);
  if (Number.isNaN(date.getTime())) {
    throw new Error("Fecha de variante invalida");
  }

  // SQL Server genera el JSON desde FOR JSON PATH.
  // Si no hay atributos, utilizar un arreglo vacio.
  const rawAttributes: unknown =
    JSON.parse(row.AtributosJson ?? "[]");

  const attributes =
    variantAttributesSchema.element.array()
      .parse(rawAttributes);

  return {
    idVariante: row.IDVariante,
    idProducto: row.IDProducto,
    sku: row.SKU,
    precioActual: row.PrecioActual,
    activa: toBoolean(row.Activa),
    fechaCreacion: date.toISOString(),
    cantidadFisica: row.CantidadFisica,
    atributos: attributes
  };
}

export async function findAdminVariants(
  actorId: number,
  input: ListAdminVariantsInput
) {
  const pool = await getDbPool();
  const result = await pool.request()
    .input("IDUsuarioActor", sql.Int, actorId)
    .input("IDProducto", sql.Int, input.idProducto)
    .input("Pagina", sql.Int, input.pagina)
    .input("TamanoPagina", sql.Int, input.tamanoPagina)
    .execute("dbo.SP_Catalogo_ListarVariantesAdmin");

  // Recordset 0: total; recordset 1: pagina de variantes.
  const sets = result.recordsets as unknown as [TotalRow[], AdminVariantRow[]];
  const totalRow = sets[0]?.[0];
  const rows = sets[1];

  if (!totalRow || !Array.isArray(rows)) {
    throw new Error("Respuesta incompleta del listado de variantes");
  }

  const totalRegistros = toSafeCount(totalRow.Total);
  return {
    items: rows.map(mapVariant),
    pagination: {
      pagina: input.pagina,
      tamanoPagina: input.tamanoPagina,
      totalRegistros,
      totalPaginas: Math.ceil(totalRegistros / input.tamanoPagina)
    }
  };
}

export async function insertAdminVariant(
  actorId: number,
  input: CreateAdminVariantInput
) {
  const pool = await getDbPool();
  const result = await pool.request()
    .input("IDUsuarioActor", sql.Int, actorId)
    .input("IDProducto", sql.Int, input.idProducto)
    .input("SKU", sql.NVarChar(64), input.sku)
    .input("PrecioActual", sql.Decimal(19, 2), Number(input.precioActual))
    .input("AtributosJson", sql.NVarChar(sql.MAX), JSON.stringify(input.atributos))
    .execute<CreatedVariantRow>("dbo.SP_Catalogo_CrearVariante");

  const row = result.recordset[0];
  if (!row) {
    throw new Error("No se recibio la variante creada");
  }

  return {
    idVariante: row.IDVariante,
    idProducto: row.IDProducto,
    sku: row.SKU,
    precioActual: row.PrecioActual,
    activa: toBoolean(row.Activa),
    cantidadFisica: row.CantidadFisica,
    atributos: input.atributos
  };
}

export async function setAdminVariantStatus(
  actorId: number,
  variantId: number,
  activa: boolean
) {
  const pool = await getDbPool();
  const result = await pool.request()
    .input("IDUsuarioActor", sql.Int, actorId)
    .input("IDVariante", sql.Int, variantId)
    .input("Activa", sql.Bit, activa)
    .execute<VariantStatusRow>("dbo.SP_Catalogo_CambiarEstadoVariante");

  const row = result.recordset[0];
  if (!row) {
    throw new Error("No se recibio el estado de la variante");
  }

  return {
    idVariante: row.IDVariante,
    idProducto: row.IDProducto,
    sku: row.SKU,
    activa: toBoolean(row.Activa),
    actualizado: toBoolean(row.Actualizado)
  };
}
