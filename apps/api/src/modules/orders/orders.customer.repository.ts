import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  CustomerOrdersQuery
} from "./orders.customer.schema.js";

type SqlId = string | number | bigint;
type SqlMoney = string | number;

interface OrderRow {
  IDPedido: SqlId;
  Estado: string;
  Subtotal: SqlMoney;
  Descuento: SqlMoney;
  Total: SqlMoney;
  CodigoCupon: string | null;
  FechaCreacion: Date | string;
  FechaActualizacion: Date | string;
}

interface OrderDetailRow extends OrderRow {
  EntregaDestinatario: string;
  EntregaTelefono: string;
  EntregaDepartamento: string;
  EntregaMunicipio: string;
  EntregaDireccionLinea1: string;
  EntregaReferencia: string | null;
}

interface ItemRow {
  IDDetallePedido: SqlId;
  IDVariante: number;
  SKU: string;
  NombreProducto: string;
  PrecioUnitario: SqlMoney;
  Cantidad: number;
  CantidadDevuelta: number;
  ImporteLinea: SqlMoney;
}

interface HistoryRow {
  IDHistorialPedido: SqlId;
  EstadoAnterior: string | null;
  EstadoNuevo: string;
  Observacion: string | null;
  FechaCambio: Date | string;
}

interface PaginationRow {
  Pagina: number;
  TamanoPagina: number;
  TotalRegistros: SqlId;
  TotalPaginas: SqlId;
}

function toId(value: SqlId): string {
  if (
    typeof value === "number" &&
    !Number.isSafeInteger(value)
  ) {
    throw new Error("ID SQL fuera del rango seguro");
  }

  const id = String(value);

  if (!/^[1-9]\d*$/.test(id)) {
    throw new Error("ID SQL invalido");
  }

  return id;
}

function toCount(value: SqlId): number {
  const count = Number(value);

  if (!Number.isSafeInteger(count) || count < 0) {
    throw new Error("Contador SQL invalido");
  }

  return count;
}

function toMoney(value: SqlMoney): string {
  if (typeof value === "string") {
    return value;
  }

  if (!Number.isFinite(value)) {
    throw new Error("Monto SQL invalido");
  }

  return value.toFixed(2);
}

function toIso(value: Date | string): string {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    throw new Error("Fecha SQL invalida");
  }

  return date.toISOString();
}

function mapOrder(row: OrderRow) {
  return {
    idPedido: toId(row.IDPedido),
    estado: row.Estado,
    subtotal: toMoney(row.Subtotal),
    descuento: toMoney(row.Descuento),
    total: toMoney(row.Total),
    codigoCupon: row.CodigoCupon,
    fechaCreacion: toIso(row.FechaCreacion),
    fechaActualizacion: toIso(
      row.FechaActualizacion
    )
  };
}

// ======================================
// LISTAR PEDIDOS PROPIOS
// ======================================

export async function listCustomerOrders(
  userId: number,
  input: CustomerOrdersQuery
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .input(
      "Estado",
      sql.VarChar(20),
      input.estado ?? null
    )
    .input("Pagina", sql.Int, input.pagina)
    .input(
      "TamanoPagina",
      sql.Int,
      input.tamanoPagina
    )
    .execute("dbo.SP_Pedidos_ListarPropios");

  const sets = result.recordsets as unknown as [
    OrderRow[],
    PaginationRow[]
  ];

  const pagination = sets[1]?.[0];

  if (!pagination) {
    throw new Error(
      "Faltan metadatos de paginacion"
    );
  }

  return {
    items: (sets[0] ?? []).map(mapOrder),
    pagination: {
      pagina: pagination.Pagina,
      tamanoPagina: pagination.TamanoPagina,
      totalRegistros: toCount(
        pagination.TotalRegistros
      ),
      totalPaginas: toCount(
        pagination.TotalPaginas
      )
    }
  };
}

// ======================================
// CONSULTAR PEDIDO E HISTORIAL
// ======================================

export async function getCustomerOrder(
  userId: number,
  orderId: string
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .input("IDPedido", sql.BigInt, orderId)
    .execute("dbo.SP_Pedidos_ObtenerPropio");

  const sets = result.recordsets as unknown as [
    OrderDetailRow[],
    ItemRow[],
    HistoryRow[]
  ];

  const order = sets[0]?.[0];

  if (!order) {
    throw new Error(
      "El SP no devolvio el pedido solicitado"
    );
  }

  return {
    ...mapOrder(order),

    direccionEntrega: {
      destinatario: order.EntregaDestinatario,
      telefono: order.EntregaTelefono,
      departamento: order.EntregaDepartamento,
      municipio: order.EntregaMunicipio,
      direccionLinea1: order.EntregaDireccionLinea1,
      referencia: order.EntregaReferencia
    },

    productos: (sets[1] ?? []).map(row => ({
      idDetallePedido: toId(row.IDDetallePedido),
      idVariante: row.IDVariante,
      sku: row.SKU,
      nombreProducto: row.NombreProducto,
      precioUnitario: toMoney(row.PrecioUnitario),
      cantidad: row.Cantidad,
      cantidadDevuelta: row.CantidadDevuelta,
      importeLinea: toMoney(row.ImporteLinea)
    })),

    historial: (sets[2] ?? []).map(row => ({
      idHistorialPedido: toId(row.IDHistorialPedido),
      estadoAnterior: row.EstadoAnterior,
      estadoNuevo: row.EstadoNuevo,
      observacion: row.Observacion,
      fechaCambio: toIso(row.FechaCambio)
    }))
  };
}
