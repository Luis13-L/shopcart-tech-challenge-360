import { getDbPool } from "../../config/database.js";

interface DatabaseHealthRow {
  Disponible: number;
  FechaServidorUTC: Date;
}

export async function verifyDatabaseConnection(): Promise<boolean> {
  const pool = await getDbPool();

  const result = await pool
    .request()
    .execute<DatabaseHealthRow>(
      "dbo.SP_Sistema_VerificarConexion"
    );

  return result.recordset?.[0]?.Disponible === 1;
}