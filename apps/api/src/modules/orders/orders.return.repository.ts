import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  ReturnOrderInput
} from "./orders.return.schema.js";

interface ReturnRow {
  IDDevolucion: string | number | bigint;
  IDPedido: string | number | bigint;
  IDDetallePedido: string | number | bigint;
  Cantidad: number;
  MontoReembolso: string | number;
  EstadoPedido: string;
  Reutilizado: boolean | number;
}

function toIdString(value: unknown): string {
  if (
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value > 0
  ) {
    return String(value);
  }

  if (typeof value === "bigint" && value > 0n) {
    return value.toString();
  }

  if (
    typeof value === "string" &&
    /^[1-9]\d*$/.test(value) &&
    BigInt(value) <= 9223372036854775807n
  ) {
    return value;
  }

  throw new Error(
    "SQL Server devolvio un identificador invalido"
  );
}

function toMoneyString(
  value: string | number
): string {
  if (typeof value === "string") {
    return value;
  }

  if (!Number.isFinite(value)) {
    throw new Error("Importe invalido");
  }

  return value.toFixed(2);
}

export async function registerOrderReturn(
  orderId: string,
  userId: number,
  input: ReturnOrderInput
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDPedido", sql.BigInt, orderId)
    .input(
      "IDDetallePedido",
      sql.BigInt,
      input.idDetallePedido
    )
    .input("IDUsuario", sql.Int, userId)
    .input("Cantidad", sql.Int, input.cantidad)
    .input("Motivo", sql.NVarChar(300), input.motivo)
    .input(
      "ClaveIdempotencia",
      sql.VarChar(100),
      input.claveIdempotencia
    )
    .execute<ReturnRow>(
      "dbo.SP_Pedidos_RegistrarDevolucion"
    );

  const row = result.recordset?.[0];

  if (!row) {
    throw new Error(
      "El SP no devolvio la devolucion"
    );
  }

  return {
    idDevolucion: toIdString(row.IDDevolucion),
    idPedido: toIdString(row.IDPedido),
    idDetallePedido: toIdString(row.IDDetallePedido),
    cantidad: row.Cantidad,
    montoReembolso: toMoneyString(
      row.MontoReembolso
    ),
    estadoPedido: row.EstadoPedido,
    reutilizado:
      row.Reutilizado === true ||
      row.Reutilizado === 1
  };
}
