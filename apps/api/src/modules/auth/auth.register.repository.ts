import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

export interface RegisteredUserRow {
  IDUsuario: number;
  Correo: string;
  NombreRol: string;
  FechaCreacion: Date | string;
}

export async function createCustomerInDatabase(
  correo: string,
  passwordHash: string
): Promise<RegisteredUserRow> {
  const pool = await getDbPool();

  const result = await pool.request()
    .input(
      "Correo",
      sql.NVarChar(254),
      correo
    )
    .input(
      "PasswordHash",
      sql.NVarChar(255),
      passwordHash
    )
    .execute<RegisteredUserRow>(
      "dbo.SP_Auth_RegistrarCliente"
    );

  const user = result.recordset[0];

  if (!user) {
    throw new Error(
      "El procedimiento no devolvio el usuario creado"
    );
  }

  return user;
}
