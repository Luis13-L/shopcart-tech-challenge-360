import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  CouponInput
} from "./coupons.schema.js";

// ==========================================
// TIPOS QUE DEVUELVE SQL SERVER
// ==========================================

type SqlMoney = number | string;
type SqlId = string | number | bigint;

interface CouponRow {
  IDCupon: number;
  Codigo: string;
  TipoDescuento: string;
  Valor: SqlMoney;
  MontoMinimo: SqlMoney;
  LimiteUsos: number;
  UsosRealizados: number;
  LimitePorCliente: number;
  FechaInicio: Date | string;
  FechaFin: Date | string;
  Activo: boolean | number;
  FechaCreacion?: Date | string;
}

interface CouponStatusRow {
  IDCupon: number;
  Codigo: string;
  Activo: boolean | number;
  UsosRealizados: number;
  LimiteUsos: number;
}

interface CouponUseRow {
  IDUsoCupon: SqlId;
  IDCupon: number;
  IDPedido: SqlId;
  IDUsuario: number;
  MontoDescuento: SqlMoney;
  FechaUso: Date | string;
}

// ==========================================
// FUNCIONES AUXILIARES
// ==========================================

function moneyString(value: SqlMoney): string {
  const amount = Number(value);

  if (!Number.isFinite(amount)) {
    throw new Error(
      "SQL Server devolvio un monto invalido"
    );
  }

  return amount.toFixed(2);
}

function idString(value: SqlId): string {
  if (
    typeof value === "number" &&
    !Number.isSafeInteger(value)
  ) {
    throw new Error(
      "Identificador BIGINT fuera del rango seguro"
    );
  }

  return String(value);
}

function dateString(
  value: Date | string
): string {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    throw new Error(
      "SQL Server devolvio una fecha invalida"
    );
  }

  return date.toISOString();
}

function mapCoupon(row: CouponRow) {
  return {
    idCupon: row.IDCupon,
    codigo: row.Codigo,
    tipoDescuento: row.TipoDescuento,
    valor: moneyString(row.Valor),
    montoMinimo: moneyString(row.MontoMinimo),
    limiteUsos: row.LimiteUsos,
    usosRealizados: row.UsosRealizados,
    limitePorCliente: row.LimitePorCliente,
    fechaInicio: dateString(row.FechaInicio),
    fechaFin: dateString(row.FechaFin),
    activo: Boolean(row.Activo),
    ...(row.FechaCreacion
      ? {
          fechaCreacion: dateString(
            row.FechaCreacion
          )
        }
      : {})
  };
}

// Evita repetir los parametros de crear/editar.
function bindCouponFields(
  request: sql.Request,
  input: CouponInput
): sql.Request {
  return request
    .input(
      "Codigo",
      sql.VarChar(50),
      input.codigo
    )
    .input(
      "TipoDescuento",
      sql.VarChar(15),
      input.tipoDescuento
    )
    .input(
      "Valor",
      sql.Decimal(19, 2),
      input.valor
    )
    .input(
      "MontoMinimo",
      sql.Decimal(19, 2),
      input.montoMinimo
    )
    .input(
      "LimiteUsos",
      sql.Int,
      input.limiteUsos
    )
    .input(
      "LimitePorCliente",
      sql.Int,
      input.limitePorCliente
    )
    .input(
      "FechaInicio",
      sql.DateTime2(3),
      new Date(input.fechaInicio)
    )
    .input(
      "FechaFin",
      sql.DateTime2(3),
      new Date(input.fechaFin)
    )
    .input(
      "Activo",
      sql.Bit,
      input.activo
    );
}

function firstRow<T>(
  rows: T[] | undefined
): T {
  const row = rows?.[0];

  if (!row) {
    throw new Error(
      "El procedimiento no devolvio datos"
    );
  }

  return row;
}

// ==========================================
// CREATE
// ==========================================

export async function createCoupon(
  userId: number,
  input: CouponInput
) {
  const pool = await getDbPool();

  const request = bindCouponFields(
    pool.request()
      .input("IDUsuario", sql.Int, userId),
    input
  );

  const result = await request.execute<CouponRow>(
    "dbo.SP_Cupones_Crear"
  );

  return mapCoupon(
    firstRow(result.recordset)
  );
}

// ==========================================
// READ - LISTAR
// ==========================================

export async function listCoupons(
  userId: number,
  onlyActive?: boolean
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .input(
      "SoloActivos",
      sql.Bit,
      onlyActive ?? null
    )
    .execute<CouponRow>(
      "dbo.SP_Cupones_Listar"
    );

  return result.recordset.map(mapCoupon);
}

// ==========================================
// READ - OBTENER POR ID
// ==========================================

export async function getCoupon(
  userId: number,
  couponId: number
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .input("IDCupon", sql.Int, couponId)
    .execute<CouponRow>(
      "dbo.SP_Cupones_Obtener"
    );

  return mapCoupon(
    firstRow(result.recordset)
  );
}

// ==========================================
// UPDATE
// ==========================================

export async function updateCoupon(
  userId: number,
  couponId: number,
  input: CouponInput
) {
  const pool = await getDbPool();

  const request = bindCouponFields(
    pool.request()
      .input("IDUsuario", sql.Int, userId)
      .input("IDCupon", sql.Int, couponId),
    input
  );

  const result = await request.execute<CouponRow>(
    "dbo.SP_Cupones_Actualizar"
  );

  return mapCoupon(
    firstRow(result.recordset)
  );
}

// ==========================================
// ACTIVAR / DESACTIVAR
// ==========================================

export async function changeCouponStatus(
  userId: number,
  couponId: number,
  active: boolean
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .input("IDCupon", sql.Int, couponId)
    .input("Activo", sql.Bit, active)
    .execute<CouponStatusRow>(
      "dbo.SP_Cupones_CambiarEstado"
    );

  const row = firstRow(result.recordset);

  return {
    idCupon: row.IDCupon,
    codigo: row.Codigo,
    activo: Boolean(row.Activo),
    usosRealizados: row.UsosRealizados,
    limiteUsos: row.LimiteUsos
  };
}

// ==========================================
// HISTORIAL DE USOS
// ==========================================

export async function listCouponUses(
  userId: number,
  couponId: number
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .input("IDCupon", sql.Int, couponId)
    .execute<CouponUseRow>(
      "dbo.SP_Cupones_ListarUsos"
    );

  return result.recordset.map(row => ({
    idUsoCupon: idString(row.IDUsoCupon),
    idCupon: row.IDCupon,
    idPedido: idString(row.IDPedido),
    idUsuario: row.IDUsuario,
    montoDescuento: moneyString(
      row.MontoDescuento
    ),
    fechaUso: dateString(row.FechaUso)
  }));
}
