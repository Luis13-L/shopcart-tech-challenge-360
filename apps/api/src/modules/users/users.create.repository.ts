import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  CreateAdminUserInput
} from "./users.create.schema.js";

// ==========================================
// CONTRATO DE SQL SERVER
// ==========================================

interface CreatedUserRow {
  IDUsuario: number;
  Correo: string;
  NombreRol: string;
  Activo: boolean | number;
  FechaCreacion: Date | string;
}

// ==========================================
// CREAR USUARIO EN BASE DE DATOS
// ==========================================

export async function createAdminUser(
  actorId: number,
  input: CreateAdminUserInput,
  passwordHash: string
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input(
      "IDUsuarioActor",
      sql.Int,
      actorId
    )
    .input(
      "Correo",
      sql.NVarChar(254),
      input.correo
    )
    .input(
      "PasswordHash",
      sql.NVarChar(255),
      passwordHash
    )
    .input(
      "Rol",
      sql.VarChar(30),
      input.rol
    )
    .execute<CreatedUserRow>(
      "dbo.SP_Usuarios_CrearAdministracion"
    );

  const user = result.recordset?.[0];

  if (!user) {
    throw new Error(
      "El procedimiento no devolvio el usuario creado"
    );
  }

  if (
    !Number.isSafeInteger(user.IDUsuario) ||
    user.IDUsuario <= 0
  ) {
    throw new Error(
      "SQL Server devolvio un ID de usuario invalido"
    );
  }

  const fechaCreacion =
    new Date(user.FechaCreacion);

  if (Number.isNaN(fechaCreacion.getTime())) {
    throw new Error(
      "SQL Server devolvio una fecha invalida"
    );
  }

  // Nunca exponer PasswordHash.

  return {
    idUsuario: user.IDUsuario,
    correo: user.Correo,
    rol: user.NombreRol,
    activo:
      user.Activo === true ||
      user.Activo === 1,
    fechaCreacion: fechaCreacion.toISOString()
  };
}
