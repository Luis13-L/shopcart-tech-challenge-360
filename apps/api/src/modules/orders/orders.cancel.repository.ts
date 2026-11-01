import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

interface CancelOrderRow {
  IDPedido: string | number | bigint;
  EstadoAnterior: string;
  EstadoNuevo: string;
  YaCancelado: boolean | number;
  FechaCambio?: Date | string | null;
}

export async function cancelOrder(
  orderId: string,
  userId: number,
  reason: string
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDPedido", sql.BigInt, orderId)
    .input("IDUsuario", sql.Int, userId)
    .input("Motivo", sql.NVarChar(200), reason)
    .execute<CancelOrderRow>(
      "dbo.SP_Pedidos_CancelarPedido"
    );

  const row = result.recordset?.[0];

  if (!row) {
    throw new Error(
      "El SP no devolvio el resultado de cancelacion"
    );
  }

  const rawId = row.IDPedido;

  if (
    typeof rawId === "number" &&
    (!Number.isSafeInteger(rawId) || rawId <= 0)
  ) {
    throw new Error(
      "SQL Server devolvio un IDPedido invalido"
    );
  }

  if (
    typeof rawId === "string" &&
    !/^[1-9]\d*$/.test(rawId)
  ) {
    throw new Error(
      "SQL Server devolvio un IDPedido invalido"
    );
  }

  return {
    idPedido: String(rawId),
    estadoAnterior: row.EstadoAnterior,
    estadoNuevo: row.EstadoNuevo,
    yaCancelado:
      row.YaCancelado === true ||
      row.YaCancelado === 1,
    fechaCambio: row.FechaCambio
      ? new Date(row.FechaCambio).toISOString()
      : null
  };
}
