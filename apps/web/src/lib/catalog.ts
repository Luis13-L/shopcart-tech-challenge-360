export interface Product {
  idProducto: number;
  nombreProducto: string;
  idCategoria: number;
  nombreCategoria: string;
  idVariante: number;
  sku: string;
  precioActual: string;
  cantidadFisica: number;
  imagenUrl: string | null;
  imagenAlt: string | null;
}

export interface Category {
  idCategoria: number;
  nombre: string;
  descripcion: string | null;
  activa: boolean;
}

export type Sort =
  | "name_asc"
  | "name_desc"
  | "price_asc"
  | "price_desc";

export interface CatalogFilters {
  search: string;
  categoryId: number | null;
  minPrice: string;
  maxPrice: string;
  available: boolean;
  sort: Sort;
  page: number;
  pageSize: number;
}

export interface CatalogResponse {
  data: Product[];

  pagination: {
    page: number;
    pageSize: number;
    total: number;
    totalPages: number;
  };
}

// ==========================================
// CLIENTE HTTP REUTILIZABLE
// ==========================================

async function getJson<T>(
  path: string,
  signal: AbortSignal
): Promise<T> {

  const response = await fetch(`/api${path}`, {
    signal,
    headers: {
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    let message =
      `No pudimos obtener la informacion (HTTP ${response.status}).`;

    try {
      const data = (await response.json()) as {
        message?: string;
      };

      if (data.message) {
        message = data.message;
      }
    } catch {
      // Puede que la respuesta no contenga JSON.
    }

    throw new Error(message);
  }

  return (await response.json()) as T;
}

// ==========================================
// GET /api/catalog/categories
// ==========================================

export function getCategories(
  signal: AbortSignal
): Promise<Category[]> {

  return getJson<{ data: Category[] }>(
    "/catalog/categories",
    signal
  ).then((result) => result.data);
}

// ==========================================
// GET /api/catalog/products
// ==========================================

export function getProducts(
  filters: CatalogFilters,
  signal: AbortSignal
): Promise<CatalogResponse> {

  const params = new URLSearchParams({
    search: filters.search,
    sort: filters.sort,
    available: String(filters.available),
    page: String(filters.page),
    pageSize: String(filters.pageSize),
  });

  if (filters.categoryId !== null) {
    params.set(
      "categoryId",
      String(filters.categoryId)
    );
  }

  if (filters.minPrice !== "") {
    params.set("minPrice", filters.minPrice);
  }

  if (filters.maxPrice !== "") {
    params.set("maxPrice", filters.maxPrice);
  }

  return getJson<CatalogResponse>(
    `/catalog/products?${params.toString()}`,
    signal
  );
}

// ==========================================
// FORMATO DE QUETZALES
// ==========================================

export function formatGTQ(
  amount: string | number
): string {

  return new Intl.NumberFormat("es-GT", {
    style: "currency",
    currency: "GTQ",
    minimumFractionDigits: 2,
  }).format(Number(amount));
}
