import {
  authorizedFetch
} from "../../lib/auth";

// ==========================================
// MODULOS QUE REGISTRAN AUDITORIA
// ==========================================

export type AuditModule =
  | "CATALOGO"
  | "INVENTARIO"
  | "CUPONES"
  | "PEDIDOS"
  | "USUARIOS";

// ==========================================
// ACCIONES ADMITIDAS EN LA BITACORA
// ==========================================

export type AuditAction =
  | "CREAR"
  | "ACTUALIZAR"
  | "DESACTIVAR"
  | "ACTIVAR"
  | "AJUSTAR"
  | "CAMBIAR_ESTADO"
  | "CANCELAR"
  | "DEVOLVER";

// ==========================================
// REGISTRO DE AUDITORIA
// ==========================================

export interface AdminAuditEntry {
  // BIGINT desde SQL Server.
  // Se mantiene como string.
  idBitacora: string;

  // Usuario que realizo la accion.
  idUsuario: number;

  modulo: AuditModule;
  entidad: string;
  idEntidad: string;
  accion: AuditAction;

  // JSON almacenado como texto en SQL.
  valoresAnteriores: string | null;
  valoresNuevos: string | null;

  fechaRegistro: string;
}

// ==========================================
// PAGINACION
// ==========================================

export interface AuditPagination {
  pagina: number;
  tamanoPagina: number;
  totalRegistros: number;
  totalPaginas: number;
}

export interface AdminAuditResponse {
  items: AdminAuditEntry[];
  pagination: AuditPagination;
}

// ==========================================
// FILTROS
// ==========================================

export interface AdminAuditFilters {
  modulo?: AuditModule | null;
  idUsuarioFiltro?: number | null;

  fechaInicio?: string | null;
  fechaFin?: string | null;

  pagina?: number;
  tamanoPagina?: number;
}

// ==========================================
// VALIDACION DE FECHA
// ==========================================

function validDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }

  const date = new Date(
    `${value}T00:00:00.000Z`
  );

  return (
    !Number.isNaN(date.getTime()) &&
    date.toISOString().slice(0, 10) === value &&
    value < "9999-12-31"
  );
}

// ==========================================
// VALIDACION DE ENTEROS SQL
// ==========================================

function validPositiveInt(
  value: number,
  maximum = 2147483647
): boolean {
  return (
    Number.isSafeInteger(value) &&
    value > 0 &&
    value <= maximum
  );
}

// ==========================================
// CONSTRUIR PARAMETROS
// ==========================================

function createAuditParams(
  filters: AdminAuditFilters
): URLSearchParams {
  const pagina = filters.pagina ?? 1;

  const tamanoPagina =
    filters.tamanoPagina ?? 20;

  if (!validPositiveInt(pagina)) {
    throw new Error(
      "Numero de pagina invalido"
    );
  }

  if (!validPositiveInt(tamanoPagina, 100)) {
    throw new Error(
      "El tamano de pagina debe estar entre 1 y 100"
    );
  }

  const params = new URLSearchParams({
    pagina: String(pagina),
    tamanoPagina: String(tamanoPagina)
  });

  // ========================================
  // MODULO
  // ========================================

  if (filters.modulo) {
    params.set(
      "modulo",
      filters.modulo
    );
  }

  // ========================================
  // USUARIO RESPONSABLE
  // ========================================

  if (
    filters.idUsuarioFiltro !== null &&
    filters.idUsuarioFiltro !== undefined
  ) {
    if (!validPositiveInt(filters.idUsuarioFiltro)) {
      throw new Error(
        "ID de usuario invalido"
      );
    }

    params.set(
      "idUsuarioFiltro",
      String(filters.idUsuarioFiltro)
    );
  }

  // ========================================
  // FECHAS OPCIONALES
  // ========================================

  const fechaInicio =
    filters.fechaInicio || undefined;

  const fechaFin =
    filters.fechaFin || undefined;

  if (
    fechaInicio !== undefined &&
    !validDate(fechaInicio)
  ) {
    throw new Error(
      "Fecha inicial invalida"
    );
  }

  if (
    fechaFin !== undefined &&
    !validDate(fechaFin)
  ) {
    throw new Error(
      "Fecha final invalida"
    );
  }

  if (
    fechaInicio &&
    fechaFin &&
    fechaInicio > fechaFin
  ) {
    throw new Error(
      "La fecha inicial no puede superar la final"
    );
  }

  if (fechaInicio) {
    params.set(
      "fechaInicio",
      fechaInicio
    );
  }

  if (fechaFin) {
    params.set(
      "fechaFin",
      fechaFin
    );
  }

  return params;
}

// ==========================================
// PROCESAR RESPUESTA HTTP
// ==========================================

async function readData<T>(
  response: Response
): Promise<T> {
  const body: unknown = await response
    .json()
    .catch(() => null);

  if (!response.ok) {
    const message =
      body !== null &&
      typeof body === "object" &&
      "message" in body &&
      typeof body.message === "string"
        ? body.message
        : `Error HTTP ${response.status}`;

    throw new Error(message);
  }

  if (
    body === null ||
    typeof body !== "object" ||
    !("data" in body)
  ) {
    throw new Error(
      "Respuesta inesperada del servidor"
    );
  }

  return (body as { data: T }).data;
}

// ==========================================
// GET /api/audit
// CONSULTA ADMINISTRATIVA PAGINADA
// ==========================================

export async function getAdminAuditLogs(
  filters: AdminAuditFilters = {},
  signal?: AbortSignal
): Promise<AdminAuditResponse> {
  const params = createAuditParams(
    filters
  );

  const response = await authorizedFetch(
    `/audit?${params.toString()}`,
    { signal }
  );

  return readData<AdminAuditResponse>(
    response
  );
}
