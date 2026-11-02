import sql from "mssql";

import {
  getDbPool
} from "../../config/database.js";

import type {
  CreateCategoryInput,
  UpdateCategoryInput
} from "./categories.schema.js";

interface CategoryRow {
  IDCategoria: number;
  Nombre: string;
  Descripcion: string | null;
  Activa: boolean | number;
  FechaCreacion?: Date | string;
}

function mapCategory(row: CategoryRow) {
  return {
    idCategoria: row.IDCategoria,
    nombre: row.Nombre,
    descripcion: row.Descripcion,
    activa: Boolean(row.Activa),

    ...(row.FechaCreacion != null
      ? {
          fechaCreacion: new Date(
            row.FechaCreacion
          ).toISOString()
        }
      : {})
  };
}

function firstRow(
  rows: CategoryRow[] | undefined
): CategoryRow {
  const row = rows?.[0];

  if (!row) {
    throw new Error(
      "El procedimiento no devolvio una categoria"
    );
  }

  return row;
}

// ==========================================
// CREAR
// ==========================================

export async function createCategory(
  actorId: number,
  input: CreateCategoryInput
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuarioActor", sql.Int, actorId)
    .input(
      "Nombre",
      sql.NVarChar(120),
      input.nombre
    )
    .input(
      "Descripcion",
      sql.NVarChar(500),
      input.descripcion ?? null
    )
    .execute<CategoryRow>(
      "dbo.SP_Catalogo_CrearCategoria"
    );

  return mapCategory(firstRow(result.recordset));
}

// ==========================================
// LISTAR CATEGORIAS
// ==========================================

export async function listCategories(
  actorId: number | null,
  includeInactive: boolean
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input(
      "IDUsuarioActor",
      sql.Int,
      actorId
    )
    .input(
      "IncluirInactivas",
      sql.Bit,
      includeInactive
    )
    .execute<CategoryRow>(
      "dbo.SP_Catalogo_ListarCategorias"
    );

  return result.recordset.map(mapCategory);
}

// ==========================================
// ACTUALIZAR
// ==========================================

export async function updateCategory(
  actorId: number,
  categoryId: number,
  input: UpdateCategoryInput
) {
  const pool = await getDbPool();

  // Diferenciar entre:
  // - descripcion no enviada
  // - descripcion enviada como null
  const changeDescription =
    Object.prototype.hasOwnProperty.call(
      input,
      "descripcion"
    );

  const result = await pool.request()
    .input("IDUsuarioActor", sql.Int, actorId)
    .input("IDCategoria", sql.Int, categoryId)
    .input(
      "Nombre",
      sql.NVarChar(120),
      input.nombre ?? null
    )
    .input(
      "Descripcion",
      sql.NVarChar(500),
      input.descripcion ?? null
    )
    .input(
      "CambiarDescripcion",
      sql.Bit,
      changeDescription
    )
    .execute<CategoryRow>(
      "dbo.SP_Catalogo_ActualizarCategoria"
    );

  return mapCategory(firstRow(result.recordset));
}

// ==========================================
// ACTIVAR / DESACTIVAR
// ==========================================

export async function changeCategoryStatus(
  actorId: number,
  categoryId: number,
  active: boolean
) {
  const pool = await getDbPool();

  const result = await pool.request()
    .input("IDUsuarioActor", sql.Int, actorId)
    .input("IDCategoria", sql.Int, categoryId)
    .input("Activa", sql.Bit, active)
    .execute<CategoryRow>(
      "dbo.SP_Catalogo_CambiarEstadoCategoria"
    );

  return mapCategory(firstRow(result.recordset));
}
