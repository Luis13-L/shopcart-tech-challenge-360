import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  SalesReportInput,
  DateRangeInput,
  OrdersReportInput
} from "./reports.schema.js";

type SqlMoney = number | string;
type SqlBigInt = number | string | bigint;

// ==========================================
// TIPOS SQL
// ==========================================

interface SalesRow {
  Periodo: Date | string;
  CantidadPedidos: number | bigint;
  VentasNetas: SqlMoney;
}

interface CategoryRow {
  IDCategoria: number;
  CantidadPedidos: number | bigint;
  UnidadesNetas: number;
  VentasNetas: SqlMoney;
}

interface ProductRow {
  IDVariante: number;
  SKU: string;
  NombreProducto: string;
  UnidadesVendidas: number;
  VentasNetas: SqlMoney;
}

interface OrderRow {
  IDPedido: SqlBigInt;
  IDUsuario: number;
  Estado: string;
  Subtotal: SqlMoney;
  Descuento: SqlMoney;
  Total: SqlMoney;
  CodigoCupon: string | null;
  MontoDevuelto: SqlMoney;
  VentaNeta: SqlMoney;
  FechaCreacion: Date | string;
  FechaActualizacion: Date | string;
}

interface PaginationRow {
  Pagina: number;
  TamanoPagina: number;
  TotalRegistros: SqlBigInt;
  TotalPaginas: SqlBigInt;
}

// ==========================================
// FUNCIONES AUXILIARES
// ==========================================

function toSqlDate(value: string): Date {
  return new Date(
    `${value}T00:00:00.000Z`
  );
}

function toMoney(value: SqlMoney): string {
  const amount = Number(value);

  if (!Number.isFinite(amount)) {
    throw new Error("Monto SQL invalido");
  }

  return amount.toFixed(2);
}

function toCount(
  value: SqlBigInt
): number {
  const count = Number(value);

  if (
    !Number.isSafeInteger(count) ||
    count < 0
  ) {
    throw new Error(
      "Contador SQL fuera del rango seguro"
    );
  }

  return count;
}

function toId(value: SqlBigInt): string {
  if (
    typeof value === "number" &&
    !Number.isSafeInteger(value)
  ) {
    throw new Error(
      "ID BIGINT fuera del rango seguro"
    );
  }

  const id = String(value);

  if (!/^[1-9]\d*$/.test(id)) {
    throw new Error("ID SQL invalido");
  }

  return id;
}

function toIsoDate(
  value: Date | string
): string {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    throw new Error("Fecha SQL invalida");
  }

  return date.toISOString();
}

function toDateOnly(
  value: Date | string
): string {
  return toIsoDate(value).slice(0, 10);
}

function bindDates(
  request: sql.Request,
  dates: DateRangeInput
): sql.Request {
  return request
    .input(
      "FechaInicio",
      sql.Date,
      toSqlDate(dates.fechaInicio)
    )
    .input(
      "FechaFin",
      sql.Date,
      toSqlDate(dates.fechaFin)
    );
}

// ==========================================
// RF-08: VENTAS POR PERIODO
// ==========================================

export async function getSalesReport(
  userId: number,
  input: SalesReportInput
) {
  const pool = await getDbPool();

  const request = bindDates(
    pool.request()
      .input("IDUsuario", sql.Int, userId)
      .input(
        "Agrupacion",
        sql.VarChar(10),
        input.agrupacion
      ),
    input
  );

  const result = await request.execute<SalesRow>(
    "dbo.SP_Reportes_VentasPeriodo"
  );

  return result.recordset.map(row => ({
    periodo: toDateOnly(row.Periodo),
    cantidadPedidos: toCount(row.CantidadPedidos),
    ventasNetas: toMoney(row.VentasNetas)
  }));
}

// ==========================================
// RF-08: VENTAS POR CATEGORIA
// ==========================================

export async function getCategoriesReport(
  userId: number,
  input: DateRangeInput
) {
  const pool = await getDbPool();

  const request = bindDates(
    pool.request()
      .input("IDUsuario", sql.Int, userId),
    input
  );

  const result = await request.execute<CategoryRow>(
    "dbo.SP_Reportes_VentasCategoria"
  );

  return result.recordset.map(row => ({
    idCategoria: row.IDCategoria,
    cantidadPedidos: toCount(row.CantidadPedidos),
    unidadesNetas: row.UnidadesNetas,
    ventasNetas: toMoney(row.VentasNetas)
  }));
}

// ==========================================
// RF-08: TOP 10 PRODUCTOS
// ==========================================

export async function getTopProductsReport(
  userId: number,
  input: DateRangeInput
) {
  const pool = await getDbPool();

  const request = bindDates(
    pool.request()
      .input("IDUsuario", sql.Int, userId),
    input
  );

  const result = await request.execute<ProductRow>(
    "dbo.SP_Reportes_TopProductos"
  );

  return result.recordset.map(row => ({
    idVariante: row.IDVariante,
    sku: row.SKU,
    nombreProducto: row.NombreProducto,
    unidadesVendidas: row.UnidadesVendidas,
    ventasNetas: toMoney(row.VentasNetas)
  }));
}

// ==========================================
// RF-08: LISTADO PAGINADO DE PEDIDOS
// ==========================================

export async function getOrdersReport(
  userId: number,
  input: OrdersReportInput
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .input(
      "Estado",
      sql.VarChar(20),
      input.estado ?? null
    )
    .input(
      "IDCliente",
      sql.Int,
      input.idCliente ?? null
    )
    .input(
      "FechaInicio",
      sql.Date,
      input.fechaInicio
        ? toSqlDate(input.fechaInicio)
        : null
    )
    .input(
      "FechaFin",
      sql.Date,
      input.fechaFin
        ? toSqlDate(input.fechaFin)
        : null
    )
    .input("Pagina", sql.Int, input.pagina)
    .input(
      "TamanoPagina",
      sql.Int,
      input.tamanoPagina
    )
    .execute(
      "dbo.SP_Reportes_ListarPedidos"
    );

  // El procedimiento devuelve DOS resultsets:
  // 0: pedidos
  // 1: metadatos de paginacion
  const recordsets = result.recordsets as unknown as [
    OrderRow[],
    PaginationRow[]
  ];

  const rows = recordsets[0] ?? [];
  const paginationRow = recordsets[1]?.[0];

  if (!paginationRow) {
    throw new Error(
      "No se recibieron metadatos de paginacion"
    );
  }

  return {
    items: rows.map(row => ({
      idPedido: toId(row.IDPedido),
      idUsuario: row.IDUsuario,
      estado: row.Estado,
      subtotal: toMoney(row.Subtotal),
      descuento: toMoney(row.Descuento),
      total: toMoney(row.Total),
      codigoCupon: row.CodigoCupon,
      montoDevuelto: toMoney(row.MontoDevuelto),
      ventaNeta: toMoney(row.VentaNeta),
      fechaCreacion: toIsoDate(
        row.FechaCreacion
      ),
      fechaActualizacion: toIsoDate(
        row.FechaActualizacion
      )
    })),

    pagination: {
      pagina: paginationRow.Pagina,
      tamanoPagina: paginationRow.TamanoPagina,
      totalRegistros: toCount(
        paginationRow.TotalRegistros
      ),
      totalPaginas: toCount(
        paginationRow.TotalPaginas
      )
    }
  };
}
