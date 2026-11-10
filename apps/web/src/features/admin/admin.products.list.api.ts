import {
  authorizedFetch
} from "../../lib/auth";

// ==========================================
// PRODUCTO ADMINISTRATIVO
// ==========================================

export interface AdminProduct {
  idProducto: number;
  nombreProducto: string;
  descripcion: string | null;
  activo: boolean;
  fechaCreacion: string;

  idCategoria: number;
  nombreCategoria: string;
  categoriaActiva: boolean;

  idVarianteReferencia: number | null;
  skuReferencia: string | null;
  precioReferencia: string | null;
  varianteReferenciaActiva: boolean | null;

  cantidadFisicaReferencia: number;
  totalVariantes: number;
  variantesActivas: number;

  imagenUrl: string | null;
  imagenAlt: string | null;
}

// ==========================================
// PAGINACION
// ==========================================

export interface AdminProductsPagination {
  pagina: number;
  tamanoPagina: number;
  totalRegistros: number;
  totalPaginas: number;
}

export interface AdminProductsResponse {
  items: AdminProduct[];
  pagination: AdminProductsPagination;
}

// ==========================================
// FILTROS
// ==========================================

export interface AdminProductsFilters {
  pagina?: number;
  tamanoPagina?: number;
  busqueda?: string;
  activo?: boolean | null;
  idCategoria?: number | null;
}

// ==========================================
// VALIDAR ENTEROS
// ==========================================

function validInt(
  value: number,
  max: number
): boolean {
  return (
    Number.isSafeInteger(value) &&
    value >= 1 &&
    value <= max
  );
}

// ==========================================
// GET /api/admin/products
// ==========================================

export async function getAdminProducts(
  filters: AdminProductsFilters = {},
  signal?: AbortSignal
): Promise<AdminProductsResponse> {
  const pagina = filters.pagina ?? 1;
  const tamanoPagina =
    filters.tamanoPagina ?? 10;

  if (!validInt(pagina, 10000)) {
    throw new Error(
      "Numero de pagina invalido"
    );
  }

  if (!validInt(tamanoPagina, 50)) {
    throw new Error(
      "Tamano de pagina invalido"
    );
  }

  const params = new URLSearchParams({
    pagina: String(pagina),
    tamanoPagina: String(tamanoPagina)
  });

  const busqueda =
    filters.busqueda?.trim() ?? "";

  if (busqueda.length > 120) {
    throw new Error(
      "La busqueda no puede superar 120 caracteres"
    );
  }

  if (busqueda) {
    params.set("busqueda", busqueda);
  }

  if (
    filters.activo !== null &&
    filters.activo !== undefined
  ) {
    params.set(
      "activo",
      filters.activo ? "1" : "0"
    );
  }

  if (
    filters.idCategoria !== null &&
    filters.idCategoria !== undefined
  ) {
    if (
      !validInt(
        filters.idCategoria,
        2147483647
      )
    ) {
      throw new Error(
        "Categoria invalida"
      );
    }

    params.set(
      "idCategoria",
      String(filters.idCategoria)
    );
  }

  const response = await authorizedFetch(
    `/admin/products?${params.toString()}`,
    { signal }
  );

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
      "Respuesta administrativa invalida"
    );
  }

  return (
    body as {
      data: AdminProductsResponse;
    }
  ).data;
}
