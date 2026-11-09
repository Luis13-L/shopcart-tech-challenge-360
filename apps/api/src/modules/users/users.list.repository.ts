import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  ListAdminUsersInput
} from "./users.list.schema.js";

// ==========================================
// CONTRATOS SQL SERVER
// ==========================================

interface AdminUserRow {
  IDUsuario: number;
  Correo: string;
  NombreRol: string;
  Activo: boolean | number;
  FechaCreacion: Date | string;
}

interface TotalRow {
  Total: number | string | bigint;
}

// ==========================================
// FUNCIONES DE TRANSFORMACION
// ==========================================

function toIsoDate(
  value: Date | string
): string {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    throw new Error(
      "Fecha de usuario invalida desde SQL Server"
    );
  }

  return date.toISOString();
}

function toSafeCount(
  value: number | string | bigint
): number {
  const count = Number(value);

  if (
    !Number.isSafeInteger(count) ||
    count < 0
  ) {
    throw new Error(
      "Contador de usuarios fuera de rango"
    );
  }

  return count;
}

function mapUser(row: AdminUserRow) {
  return {
    idUsuario: row.IDUsuario,
    correo: row.Correo,
    rol: row.NombreRol,
    activo:
      row.Activo === true ||
      row.Activo === 1,
    fechaCreacion: toIsoDate(
      row.FechaCreacion
    )
  };
}

// ==========================================
// CONSULTAR USUARIOS ADMINISTRATIVOS
// ==========================================

export async function listAdminUsers(
  actorId: number,
  input: ListAdminUsersInput
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input(
      "IDUsuarioActor",
      sql.Int,
      actorId
    )
    .input(
      "Pagina",
      sql.Int,
      input.pagina
    )
    .input(
      "TamanoPagina",
      sql.Int,
      input.tamanoPagina
    )
    .input(
      "Busqueda",
      sql.NVarChar(254),
      input.busqueda
    )
    .input(
      "Rol",
      sql.VarChar(30),
      input.rol
    )
    .input(
      "Activo",
      sql.Bit,
      input.activo
    )
    .execute(
      "dbo.SP_Usuarios_ListarAdministracion"
    );

  // Resultset 0: usuarios
  // Resultset 1: total de registros

  const recordsets = result.recordsets as unknown as [
      AdminUserRow[],
      TotalRow[]
    ];

  if (recordsets.length < 2) {
    throw new Error(
      "SQL Server no devolvio los dos resultados"
    );
  }

  const rows = recordsets[0] ?? [];
  const totalRow = recordsets[1]?.[0];

  if (!totalRow) {
    throw new Error(
      "No se recibio el total de usuarios"
    );
  }

  const totalRegistros = toSafeCount(
    totalRow.Total
  );

  return {
    items: rows.map(mapUser),

    pagination: {
      pagina: input.pagina,
      tamanoPagina: input.tamanoPagina,
      totalRegistros,
      totalPaginas: Math.ceil(
        totalRegistros / input.tamanoPagina
      )
    }
  };
}
