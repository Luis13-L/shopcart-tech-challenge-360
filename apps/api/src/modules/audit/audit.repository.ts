import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  AuditQueryInput
} from "./audit.schema.js";

type SqlBigInt = string | number | bigint;

interface AuditRow {
  IDBitacora: SqlBigInt;
  IDUsuario: number;
  Modulo: string;
  Entidad: string;
  IDEntidad: string;
  Accion: string;
  ValoresAnteriores: string | null;
  ValoresNuevos: string | null;
  FechaRegistro: Date | string;
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

  const result = String(value);

  if (!/^[1-9]\d*$/.test(result)) {
    throw new Error("ID de auditoria invalido");
  }

  return result;
}

function toCount(value: SqlBigInt): number {
  const result = Number(value);

  if (
    !Number.isSafeInteger(result) ||
    result < 0
  ) {
    throw new Error(
      "Contador fuera del rango seguro"
    );
  }

  return result;
}

function toSqlDate(value?: string): Date | null {
  return value
    ? new Date(`${value}T00:00:00.000Z`)
    : null;
}

function toIsoDate(value: Date | string): string {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    throw new Error("Fecha invalida");
  }

  return date.toISOString();
}

export async function listAuditLogs(
  userId: number,
  filters: AuditQueryInput
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .input(
      "Modulo",
      sql.VarChar(30),
      filters.modulo ?? null
    )
    .input(
      "IDUsuarioFiltro",
      sql.Int,
      filters.idUsuarioFiltro ?? null
    )
    .input(
      "FechaInicio",
      sql.Date,
      toSqlDate(filters.fechaInicio)
    )
    .input(
      "FechaFin",
      sql.Date,
      toSqlDate(filters.fechaFin)
    )
    .input("Pagina", sql.Int, filters.pagina)
    .input(
      "TamanoPagina",
      sql.Int,
      filters.tamanoPagina
    )
    .execute("dbo.SP_Auditoria_Listar");

  const recordsets = result.recordsets as unknown as [
    AuditRow[],
    PaginationRow[]
  ];

  const rows = recordsets[0] ?? [];
  const page = recordsets[1]?.[0];

  if (!page) {
    throw new Error(
      "El SP no devolvio la paginacion"
    );
  }

  return {
    items: rows.map(row => ({
      idBitacora: toId(row.IDBitacora),
      idUsuario: row.IDUsuario,
      modulo: row.Modulo,
      entidad: row.Entidad,
      idEntidad: row.IDEntidad,
      accion: row.Accion,
      valoresAnteriores: row.ValoresAnteriores,
      valoresNuevos: row.ValoresNuevos,
      fechaRegistro: toIsoDate(row.FechaRegistro)
    })),

    pagination: {
      pagina: page.Pagina,
      tamanoPagina: page.TamanoPagina,
      totalRegistros: toCount(
        page.TotalRegistros
      ),
      totalPaginas: toCount(
        page.TotalPaginas
      )
    }
  };
}
