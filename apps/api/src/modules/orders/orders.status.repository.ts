import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  ChangeOrderStatusInput
} from "./orders.status.schema.js";

interface StatusResult {
  IDPedido: number | string | bigint;
  EstadoAnterior: string;
  EstadoNuevo: string;
  FechaCambio: Date | string;
}

export async function updateOrderStatus(
  orderId: string,
  userId: number,
  input: ChangeOrderStatusInput
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDPedido", sql.BigInt, orderId)
    .input("IDUsuario", sql.Int, userId)
    .input(
      "EstadoNuevo",
      sql.VarChar(20),
      input.estadoNuevo
    )
    .input(
      "Observacion",
      sql.NVarChar(300),
      input.observacion ?? null
    )
    .execute<StatusResult>(
      "dbo.SP_Pedidos_CambiarEstado"
    );

  const row = result.recordset?.[0];

  if (!row) {
    throw new Error(
      "El SP no devolvio el estado actualizado"
    );
  }

  const id = row.IDPedido;

  if (
    typeof id === "number" &&
    !Number.isSafeInteger(id)
  ) {
    throw new Error(
      "SQL Server devolvio un IDPedido impreciso"
    );
  }

  return {
    idPedido: String(id),
    estadoAnterior: row.EstadoAnterior,
    estadoNuevo: row.EstadoNuevo,
    fechaCambio: new Date(
      row.FechaCambio
    ).toISOString()
  };
}
