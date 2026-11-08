import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  QuoteCouponInput
} from "./checkout.quote.schema.js";

// ==========================================
// TIPOS DEVUELTOS POR SQL SERVER
// ==========================================

type SqlId = string | number | bigint;
type SqlMoney = string | number;

interface CouponQuoteRow {
  IDCarrito: SqlId;
  CodigoCupon: string;
  TipoDescuento: string;
  Valor: SqlMoney;
  IDCategoriaAplicable: number | null;
  Subtotal: SqlMoney;
  SubtotalElegible: SqlMoney;
  Descuento: SqlMoney;
  Total: SqlMoney;
}

// ==========================================
// FORMATO SEGURO DE IDENTIFICADORES
// ==========================================

function formatId(value: SqlId): string {
  if (
    typeof value === "number" &&
    !Number.isSafeInteger(value)
  ) {
    throw new Error(
      "Identificador fuera del rango seguro"
    );
  }

  const id = String(value);

  if (
    !/^[1-9]\d*$/.test(id) ||
    BigInt(id) > 9223372036854775807n
  ) {
    throw new Error(
      "Identificador invalido desde SQL Server"
    );
  }

  return id;
}

// ==========================================
// FORMATO MONETARIO
// SQL CALCULA; TYPESCRIPT SOLO FORMATEA
// ==========================================

function formatMoney(
  value: SqlMoney
): string {
  if (typeof value === "number") {
    if (
      !Number.isFinite(value) ||
      value < 0 ||
      value > Number.MAX_SAFE_INTEGER / 100
    ) {
      throw new Error(
        "Importe fuera del rango seguro"
      );
    }

    return value.toFixed(2);
  }

  if (!/^\d+(?:\.\d{1,2})?$/.test(value)) {
    throw new Error(
      "Formato monetario invalido desde SQL Server"
    );
  }

  const [integer, fraction = ""] =
    value.split(".");

  return `${integer}.${fraction.padEnd(2, "0")}`;
}

// ==========================================
// TIPO DE DESCUENTO
// ==========================================

function formatDiscountType(
  value: string
): "PORCENTAJE" | "MONTO_FIJO" {
  if (
    value !== "PORCENTAJE" &&
    value !== "MONTO_FIJO"
  ) {
    throw new Error(
      "Tipo de descuento inesperado"
    );
  }

  return value;
}

// ==========================================
// EXECUTE STORED PROCEDURE
// ==========================================

export async function quoteCoupon(
  userId: number,
  input: QuoteCouponInput
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input(
      "IDUsuario",
      sql.Int,
      userId
    )
    .input(
      "IDCarrito",
      sql.BigInt,
      input.idCarrito
    )
    .input(
      "CodigoCupon",
      sql.VarChar(50),
      input.codigoCupon
    )
    .execute<CouponQuoteRow>(
      "dbo.SP_Cupones_Cotizar"
    );

  const row = result.recordset?.[0];

  if (!row) {
    throw new Error(
      "El procedimiento no devolvio cotizacion"
    );
  }

  return {
    idCarrito: formatId(row.IDCarrito),
    codigoCupon: row.CodigoCupon,
    tipoDescuento:
      formatDiscountType(row.TipoDescuento),
    valor: formatMoney(row.Valor),
    idCategoriaAplicable:
      row.IDCategoriaAplicable,
    subtotal: formatMoney(row.Subtotal),
    subtotalElegible:
      formatMoney(row.SubtotalElegible),
    descuento: formatMoney(row.Descuento),
    total: formatMoney(row.Total)
  };
}
