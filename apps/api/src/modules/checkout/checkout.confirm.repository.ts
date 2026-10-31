import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  ConfirmCheckoutInput
} from "./checkout.confirm.schema.js";

interface CheckoutRow {
  IDPedido: string | number | bigint;
  IDCarrito: string | number | bigint;
  IDReserva: string | number | bigint;
  Estado: string;
  Subtotal: string | number;
  Descuento: string | number;
  Total: string | number;
  Reutilizado: boolean | number;
}

function toBigIntString(value: unknown): string {
  if (
    typeof value === "bigint" &&
    value > 0n
  ) {
    return value.toString();
  }

  if (
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value > 0
  ) {
    return String(value);
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

export async function confirmCheckout(
  userId: number,
  input: ConfirmCheckoutInput
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .input("IDReserva", sql.BigInt, input.idReserva)
    .input("IDDireccion", sql.Int, input.idDireccion)
    .input(
      "ClaveIdempotencia",
      sql.VarChar(100),
      input.claveIdempotencia
    )
    .input(
      "TotalEsperado",
      sql.Decimal(19, 2),
      input.totalEsperado
    )
    .execute<CheckoutRow>(
      "dbo.SP_Pedidos_ConfirmarCheckout"
    );

  const row = result.recordset?.[0];

  if (!row) {
    throw new Error(
      "El checkout no devolvio un pedido"
    );
  }

  return {
    idPedido: toBigIntString(row.IDPedido),
    idCarrito: toBigIntString(row.IDCarrito),
    idReserva: toBigIntString(row.IDReserva),
    estado: row.Estado,
    subtotal: toMoneyString(row.Subtotal),
    descuento: toMoneyString(row.Descuento),
    total: toMoneyString(row.Total),
    reutilizado:
      row.Reutilizado === true ||
      row.Reutilizado === 1
  };
}
