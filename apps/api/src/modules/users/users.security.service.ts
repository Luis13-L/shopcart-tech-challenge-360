import type {
  ChangeUserRoleInput
} from "./users.security.schema.js";

import {
  updateUserRole,
  updateUserStatus
} from "./users.security.repository.js";

export const usersSecurityService = {

  changeRole(
    actorId: number,
    targetId: number,
    rol: ChangeUserRoleInput["rol"]
  ) {
    return updateUserRole(
      actorId,
      targetId,
      rol
    );
  },

  changeStatus(
    actorId: number,
    targetId: number,
    activo: boolean
  ) {
    return updateUserStatus(
      actorId,
      targetId,
      activo
    );
  }
};
