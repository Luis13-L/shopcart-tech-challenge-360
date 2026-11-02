import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

interface CreatedRefreshRow {
  IDUsuario: number;
  IDFamilia: string;
  ExpiraEn: Date | string;
}

export interface RotatedRefreshRow {
  Codigo: string;
  IDUsuario: number | null;
  Correo: string | null;
  NombreRol: string | null;
  ExpiraEn: Date | string | null;
}

interface RevokedRefreshRow {
  Revocados: number;
}

export async function saveRefreshToken(
  userId: number,
  tokenHash: Buffer
): Promise<void> {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .input("TokenHash", sql.Binary, tokenHash)
    .execute<CreatedRefreshRow>(
      "dbo.SP_Auth_CrearRefreshToken"
    );

  if (!result.recordset[0]) {
    throw new Error(
      "No se pudo crear la sesion"
    );
  }
}

export async function rotateRefreshTokenInDatabase(
  currentHash: Buffer,
  newHash: Buffer
): Promise<RotatedRefreshRow> {
  const pool = await getDbPool();

  const result = await pool.request()
    .input(
      "TokenActualHash",
      sql.Binary,
      currentHash
    )
    .input(
      "TokenNuevoHash",
      sql.Binary,
      newHash
    )
    .execute<RotatedRefreshRow>(
      "dbo.SP_Auth_RotarRefreshToken"
    );

  const row = result.recordset[0];

  if (!row) {
    throw new Error(
      "El procedimiento no devolvio resultado"
    );
  }

  return row;
}

export async function revokeRefreshTokenInDatabase(
  tokenHash: Buffer
): Promise<number> {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("TokenHash", sql.Binary, tokenHash)
    .execute<RevokedRefreshRow>(
      "dbo.SP_Auth_RevocarRefreshToken"
    );

  return result.recordset[0]?.Revocados ?? 0;
}
