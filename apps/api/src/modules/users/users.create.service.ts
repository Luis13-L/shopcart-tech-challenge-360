import bcrypt from "bcryptjs";

import type {
  CreateAdminUserInput
} from "./users.create.schema.js";

import {
  createAdminUser
} from "./users.create.repository.js";

// ==========================================
// CREACION ADMINISTRATIVA DE USUARIOS
// ==========================================

export async function createAdminUserService(
  actorId: number,
  input: CreateAdminUserInput
) {
  // Generar hash bcrypt antes de acceder
  // a SQL Server.
  //
  // Nunca registrar la contrasena original
  // ni su hash en logs de aplicacion.

  const passwordHash = await bcrypt.hash(
    input.password,
    12
  );

  // SQL Server comprueba permisos,
  // unicidad y registra la auditoria.

  return createAdminUser(
    actorId,
    input,
    passwordHash
  );
}
