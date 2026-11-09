import type {
  ListAdminUsersInput
} from "./users.list.schema.js";

import {
  listAdminUsers
} from "./users.list.repository.js";

// ==========================================
// SERVICIO DE ADMINISTRACION DE USUARIOS
// ==========================================

export async function listAdminUsersService(
  actorId: number,
  input: ListAdminUsersInput
) {
  return listAdminUsers(actorId, input);
}
