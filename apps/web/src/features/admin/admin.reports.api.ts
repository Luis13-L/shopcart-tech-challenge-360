import {
  authorizedFetch
} from "../../lib/auth";

// ==========================================
// FILTROS DE FECHAS
// ==========================================

export interface ReportDateRange {
  fechaInicio: string;
  fechaFin: string;
}

export type SalesGrouping =
  | "DIA"
  | "SEMANA"
  | "MES";

export interface SalesReportFilters
  extends ReportDateRange {
  agrupacion: SalesGrouping;
}

// ==========================================
// REPORTE DE VENTAS POR PERIODO
// ==========================================

export interface SalesReportRow {
  periodo: string;
  cantidadPedidos: number;

  // El backend entrega importes DECIMAL
  // como cadenas para conservar precision.
  ventasNetas: string;
}

// ==========================================
// REPORTE DE VENTAS POR CATEGORIA
// ==========================================

export interface CategorySalesReportRow {
  idCategoria: number;
  cantidadPedidos: number;
  unidadesNetas: number;
  ventasNetas: string;
}

// ==========================================
// TOP 10 PRODUCTOS
// ==========================================

export interface TopProductReportRow {
  idVariante: number;
  sku: string;
  nombreProducto: string;
  unidadesVendidas: number;
  ventasNetas: string;
}

// ==========================================
// MANEJAR RESPUESTAS HTTP
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
// VALIDAR RANGO DE FECHAS
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

function createDateParams(
  range: ReportDateRange
): URLSearchParams {
  if (
    !validDate(range.fechaInicio) ||
    !validDate(range.fechaFin) ||
    range.fechaInicio > range.fechaFin
  ) {
    throw new Error(
      "El rango de fechas del reporte es invalido"
    );
  }

  return new URLSearchParams({
    fechaInicio: range.fechaInicio,
    fechaFin: range.fechaFin
  });
}

// ==========================================
// GET /api/reports/sales
// ==========================================

export async function getSalesReport(
  filters: SalesReportFilters,
  signal?: AbortSignal
): Promise<SalesReportRow[]> {
  const params = createDateParams(filters);

  params.set(
    "agrupacion",
    filters.agrupacion
  );

  const response = await authorizedFetch(
    `/reports/sales?${params.toString()}`,
    { signal }
  );

  return readData<SalesReportRow[]>(
    response
  );
}

// ==========================================
// GET /api/reports/categories
// ==========================================

export async function getCategorySalesReport(
  filters: ReportDateRange,
  signal?: AbortSignal
): Promise<CategorySalesReportRow[]> {
  const params = createDateParams(filters);

  const response = await authorizedFetch(
    `/reports/categories?${params.toString()}`,
    { signal }
  );

  return readData<CategorySalesReportRow[]>(
    response
  );
}

// ==========================================
// GET /api/reports/top-products
// ==========================================

export async function getTopProductsReport(
  filters: ReportDateRange,
  signal?: AbortSignal
): Promise<TopProductReportRow[]> {
  const params = createDateParams(filters);

  const response = await authorizedFetch(
    `/reports/top-products?${params.toString()}`,
    { signal }
  );

  return readData<TopProductReportRow[]>(
    response
  );
}
