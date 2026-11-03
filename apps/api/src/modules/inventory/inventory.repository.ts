import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  InventoryMovementInput,
  InventoryKardexQuery
} from "./inventory.schema.js";

type SqlBigInt = number | string | bigint;

interface MovementRow {
  IDMovimientoInventario: SqlBigInt;
  IDVariante: number;
  IDUsuario?: number;
  TipoMovimiento: string;
  CantidadFirmada: number;
  SaldoAnterior: number;
  SaldoPosterior: number;
  Motivo?: string;
  FechaMovimiento: Date | string;
}

interface StockRow {
  IDVariante: number;
  SKU: string;
  CantidadFisica: number;
  CantidadReservada: SqlBigInt;
  CantidadDisponible: SqlBigInt;
  FechaActualizacion: Date | string;
}

interface PaginationRow {
  Pagina: number;
  TamanoPagina: number;
  TotalRegistros: SqlBigInt;
  TotalPaginas: SqlBigInt;
}

function toId(value: SqlBigInt): string {
  if (
    typeof value === "number" &&
    !Number.isSafeInteger(value)
  ) {
    throw new Error("ID fuera del rango seguro");
  }

  return String(value);
}

function toCount(value: SqlBigInt): number {
  const count = Number(value);

  if (!Number.isSafeInteger(count) || count < 0) {
    throw new Error("Cantidad SQL invalida");
  }

  return count;
}

function toIso(value: Date | string): string {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    throw new Error("Fecha SQL invalida");
  }

  return date.toISOString();
}

function mapMovement(row: MovementRow) {
  return {
    idMovimientoInventario: toId(
      row.IDMovimientoInventario
    ),
    idVariante: row.IDVariante,
    ...(row.IDUsuario != null
      ? { idUsuario: row.IDUsuario }
      : {}),
    tipoMovimiento: row.TipoMovimiento,
    cantidadFirmada: row.CantidadFirmada,
    saldoAnterior: row.SaldoAnterior,
    saldoPosterior: row.SaldoPosterior,
    ...(row.Motivo != null
      ? { motivo: row.Motivo }
      : {}),
    fechaMovimiento: toIso(row.FechaMovimiento)
  };
}

// REGISTRAR MOVIMIENTO
export async function registerMovement(
  actorId: number,
  input: InventoryMovementInput
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDVariante", sql.Int, input.idVariante)
    .input("IDUsuario", sql.Int, actorId)
    .input(
      "TipoMovimiento",
      sql.VarChar(20),
      input.tipoMovimiento
    )
    .input("Cantidad", sql.Int, input.cantidad)
    .input("Motivo", sql.NVarChar(300), input.motivo)
    .execute<MovementRow>(
      "dbo.SP_Inventario_RegistrarMovimiento"
    );

  const row = result.recordset[0];

  if (!row) {
    throw new Error("No se registro el movimiento");
  }

  return mapMovement(row);
}

// CONSULTAR EXISTENCIA
export async function getInventoryStock(
  actorId: number,
  variantId: number
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, actorId)
    .input("IDVariante", sql.Int, variantId)
    .execute<StockRow>(
      "dbo.SP_Inventario_ConsultarExistencia"
    );

  const row = result.recordset[0];

  if (!row) return null;

  return {
    idVariante: row.IDVariante,
    sku: row.SKU,
    cantidadFisica: row.CantidadFisica,
    cantidadReservada: toCount(row.CantidadReservada),
    cantidadDisponible: toCount(row.CantidadDisponible),
    fechaActualizacion: toIso(
      row.FechaActualizacion
    )
  };
}

// CONSULTAR KARDEX
export async function getInventoryKardex(
  actorId: number,
  variantId: number,
  input: InventoryKardexQuery
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, actorId)
    .input("IDVariante", sql.Int, variantId)
    .input("Pagina", sql.Int, input.pagina)
    .input("TamanoPagina", sql.Int, input.tamanoPagina)
    .execute("dbo.SP_Inventario_ListarKardex");

  const sets = result.recordsets as unknown as [
    MovementRow[],
    PaginationRow[]
  ];

  const page = sets[1]?.[0];

  if (!page) {
    throw new Error("Faltan metadatos del kardex");
  }

  return {
    items: (sets[0] ?? []).map(mapMovement),
    pagination: {
      pagina: page.Pagina,
      tamanoPagina: page.TamanoPagina,
      totalRegistros: toCount(page.TotalRegistros),
      totalPaginas: toCount(page.TotalPaginas)
    }
  };
}
