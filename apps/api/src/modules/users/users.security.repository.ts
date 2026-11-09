import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  ChangeUserRoleInput
} from "./users.security.schema.js";

interface UserSecurityRow {
  IDUsuario: number;
  Correo: string;
  NombreRol: string;
  Activo: boolean | number;
  FechaCreacion: Date | string;
}

type UserRole = ChangeUserRoleInput["rol"];

type SecurityChange =
  | { rol: UserRole; activo?: never }
  | { activo: boolean; rol?: never };

// ==========================================
// TRANSFORMAR RESPUESTA
// ==========================================

function mapUser(row: UserSecurityRow) {
  const fecha = new Date(row.FechaCreacion);

  if (
    !Number.isSafeInteger(row.IDUsuario) ||
    row.IDUsuario <= 0 ||
    Number.isNaN(fecha.getTime())
  ) {
    throw new Error(
      "Datos de usuario invalidos desde SQL Server"
    );
  }

  return {
    idUsuario: row.IDUsuario,
    correo: row.Correo,
    rol: row.NombreRol,
    activo:
      row.Activo === true ||
      row.Activo === 1,
    fechaCreacion: fecha.toISOString()
  };
}

// ==========================================
// EJECUTAR CAMBIO DE SEGURIDAD
// ==========================================

async function executeSecurityChange(
  actorId: number,
  targetId: number,
  change: SecurityChange
) {
  const pool = await getDbPool();

  const request = pool.request()
    .input(
      "IDUsuarioActor",
      sql.Int,
      actorId
    )
    .input(
      "IDUsuarioObjetivo",
      sql.Int,
      targetId
    );

  if (change.rol !== undefined) {
    request.input(
      "Rol",
      sql.VarChar(30),
      change.rol
    );
  } else {
    request.input(
      "Activo",
      sql.Bit,
      change.activo
    );
  }

  const result = await request.execute<UserSecurityRow>(
    "dbo.SP_Usuarios_ActualizarSeguridadAdministracion"
  );

  const user = result.recordset?.[0];

  if (!user) {
    throw new Error(
      "SQL Server no devolvio el usuario actualizado"
    );
  }

  return mapUser(user);
}

// ==========================================
// CAMBIAR ROL
// ==========================================

export function updateUserRole(
  actorId: number,
  targetId: number,
  rol: UserRole
) {
  return executeSecurityChange(
    actorId,
    targetId,
    { rol }
  );
}

// ==========================================
// ACTIVAR / DESACTIVAR
// ==========================================

export function updateUserStatus(
  actorId: number,
  targetId: number,
  activo: boolean
) {
  return executeSecurityChange(
    actorId,
    targetId,
    { activo }
  );
}
