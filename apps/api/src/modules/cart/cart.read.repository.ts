
import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

interface CartSummaryRow {
  IDCarrito: number | string | bigint;
  CantidadLineas: number;
  Subtotal: number | string;
  Descuento: number | string;
  Total: number | string;
}

interface CartItemRow {
  IDDetalleCarrito: number | string | bigint;
  IDVariante: number;
  SKU: string;
  NombreProducto: string;
  PrecioUnitario: number | string;
  Cantidad: number;
  ImporteLinea: number | string;
}

// Convertir identificadores BIGINT a texto
function formatId(
  value: number | string | bigint
): string {
  if (
    typeof value === "number" &&
    !Number.isSafeInteger(value)
  ) {
    throw new Error("Identificador fuera de rango seguro");
  }

  const id = String(value);

  if (!/^[1-9]\d*$/.test(id)) {
    throw new Error("Identificador invalido");
  }

  return id;
}

// Formatear importes recibidos de SQL Server
// No realiza calculos monetarios.
function formatMoney(
  value: number | string
): string {
  if (typeof value === "number") {
    if (
      !Number.isFinite(value) ||
      value < 0 ||
      value > Number.MAX_SAFE_INTEGER / 100
    ) {
      throw new Error("Importe fuera de rango");
    }

    return value.toFixed(2);
  }

  if (!/^\d+(\.\d{1,2})?$/.test(value)) {
    throw new Error("Formato monetario invalido");
  }

  const [integer, fraction = ""] = value.split(".");

  return `${integer}.${fraction.padEnd(2, "0")}`;
}

export async function findCartDetails(
  cartId: string,
  userId: number
) {
  const pool = await getDbPool();

  const result = await pool
    .request()
    .input("IDCarrito", sql.BigInt, cartId)
    .input("IDUsuario", sql.Int, userId)
    .input("TokenInvitadoHash", sql.Binary, null)
    .execute("dbo.SP_Carrito_ObtenerDetalle");

  const recordsets = result.recordsets;

  // El SP debe devolver resumen y detalle
  if (
    !Array.isArray(recordsets) ||
    recordsets.length < 2
  ) {
    throw new Error(
      "El SP no devolvio los dos resultados esperados"
    );
  }

  const summary = recordsets[0]?.[0] as
    | CartSummaryRow
    | undefined;

  if (!summary) {
    throw new Error(
      "El SP no devolvio el resumen del carrito"
    );
  }

  const items = (
    recordsets[1] ?? []
  ) as CartItemRow[];

  return {
    idCarrito: formatId(summary.IDCarrito),
    cantidadLineas: summary.CantidadLineas,
    subtotal: formatMoney(summary.Subtotal),
    descuento: formatMoney(summary.Descuento),
    total: formatMoney(summary.Total),

    items: items.map(item => ({
      idDetalleCarrito: formatId(
        item.IDDetalleCarrito
      ),
      idVariante: item.IDVariante,
      sku: item.SKU,
      nombreProducto: item.NombreProducto,
      precioUnitario: formatMoney(
        item.PrecioUnitario
      ),
      cantidad: item.Cantidad,
      importeLinea: formatMoney(
        item.ImporteLinea
      )
    }))
  };
}
