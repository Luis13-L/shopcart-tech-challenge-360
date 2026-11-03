import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  CreateAddressInput
} from "./addresses.schema.js";

interface AddressRow {
  IDDireccion: number;
  Destinatario: string;
  Telefono: string;
  Departamento: string;
  Municipio: string;
  DireccionLinea1: string;
  Referencia: string | null;
  Activa: boolean | number;
  FechaCreacion: Date | string;
}

function mapAddress(row: AddressRow) {
  return {
    idDireccion: row.IDDireccion,
    destinatario: row.Destinatario,
    telefono: row.Telefono,
    departamento: row.Departamento,
    municipio: row.Municipio,
    direccionLinea1: row.DireccionLinea1,
    referencia: row.Referencia,
    activa: Boolean(row.Activa),
    fechaCreacion: new Date(
      row.FechaCreacion
    ).toISOString()
  };
}

// ======================================
// CREAR DIRECCION
// ======================================

export async function createAddress(
  userId: number,
  input: CreateAddressInput
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .input(
      "Destinatario",
      sql.NVarChar(150),
      input.destinatario
    )
    .input(
      "Telefono",
      sql.NVarChar(25),
      input.telefono
    )
    .input(
      "Departamento",
      sql.NVarChar(100),
      input.departamento
    )
    .input(
      "Municipio",
      sql.NVarChar(100),
      input.municipio
    )
    .input(
      "DireccionLinea1",
      sql.NVarChar(250),
      input.direccionLinea1
    )
    .input(
      "Referencia",
      sql.NVarChar(250),
      input.referencia
    )
    .execute<AddressRow>(
      "dbo.SP_Direcciones_CrearCliente"
    );

  const address = result.recordset[0];

  if (!address) {
    throw new Error(
      "El procedimiento no devolvio la direccion creada"
    );
  }

  return mapAddress(address);
}

// ======================================
// LISTAR DIRECCIONES
// ======================================

export async function listAddresses(
  userId: number
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .execute<AddressRow>(
      "dbo.SP_Direcciones_ListarCliente"
    );

  return result.recordset.map(mapAddress);
}

// ======================================
// CONSULTAR DIRECCION
// ======================================

export async function getAddress(
  userId: number,
  addressId: number
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuario", sql.Int, userId)
    .input("IDDireccion", sql.Int, addressId)
    .execute<AddressRow>(
      "dbo.SP_Direcciones_ObtenerCliente"
    );

  const row = result.recordset[0];

  return row ? mapAddress(row) : null;
}
