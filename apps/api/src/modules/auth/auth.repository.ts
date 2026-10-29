
import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

export interface AuthUser {
  IDUsuario: number;
  Correo: string;
  PasswordHash: string;
  IDRol: number;
  NombreRol: string;
}

export async function findUserByEmail(
  correo: string
): Promise<AuthUser | null> {
  const pool = await getDbPool();

  const result = await pool
    .request()
    .input("Correo", sql.NVarChar(254), correo)
    .execute<AuthUser>(
      "dbo.SP_Auth_ObtenerUsuarioPorCorreo"
    );

  return result.recordset[0] ?? null;
}
