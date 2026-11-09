import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

interface CurrentPrincipalRow {
  IDUsuario: number;
  NombreRol: string;
  VersionSeguridad: number | string | bigint;
}

export interface CurrentPrincipal {
  id: number;
  role: string;
  securityVersion: string;
}

// ==========================================
// CONSULTAR USUARIO ACTIVO Y VERSION
// ==========================================

export async function getCurrentPrincipal(
  userId: number
): Promise<CurrentPrincipal | null> {
  const pool = await getDbPool();

  const result = await pool.request()
    .input(
      "IDUsuario",
      sql.Int,
      userId
    )
    .execute<CurrentPrincipalRow>(
      "dbo.SP_Auth_ObtenerPrincipalActual"
    );

  const row = result.recordset?.[0];

  if (!row) {
    return null;
  }

  if (
    !Number.isSafeInteger(row.IDUsuario) ||
    row.IDUsuario !== userId
  ) {
    throw new Error(
      "SQL Server devolvio un usuario invalido"
    );
  }

  if (
    ![
      "Cliente",
      "Operador",
      "Administrador"
    ].includes(row.NombreRol)
  ) {
    throw new Error(
      "SQL Server devolvio un rol invalido"
    );
  }

  // BIGINT se representa como cadena
  // para evitar perdida de precision.

  if (
    typeof row.VersionSeguridad === "number" &&
    !Number.isSafeInteger(row.VersionSeguridad)
  ) {
    throw new Error(
      "Version de seguridad fuera de rango"
    );
  }

  const securityVersion =
    String(row.VersionSeguridad);

  if (!/^[1-9]\d*$/.test(securityVersion)) {
    throw new Error(
      "Version de seguridad invalida"
    );
  }

  return {
    id: row.IDUsuario,
    role: row.NombreRol,
    securityVersion
  };
}
