import { authorizedFetch } from "../../lib/auth";

export interface VariantAttribute {
  nombre: string;
  valor: string;
}

export interface AdminVariant {
  idVariante: number;
  idProducto: number;
  sku: string;
  precioActual: string;
  activa: boolean;
  fechaCreacion: string;
  cantidadFisica: number;
  atributos: VariantAttribute[];
}

export interface AdminVariantPagination {
  pagina: number;
  tamanoPagina: number;
  totalRegistros: number;
  totalPaginas: number;
}

export interface AdminVariantsResult {
  items: AdminVariant[];
  pagination: AdminVariantPagination;
}

export interface CreateAdminVariantInput {
  idProducto: number;
  sku: string;
  precioActual: string;
  atributos: VariantAttribute[];
}

export interface CreatedAdminVariant {
  idVariante: number;
  idProducto: number;
  sku: string;
  precioActual: string;
  activa: boolean;
  cantidadFisica: number;
  atributos: VariantAttribute[];
}

export interface ChangedVariantStatus {
  idVariante: number;
  idProducto: number;
  sku: string;
  activa: boolean;
  actualizado: boolean;
}

async function readData<T>(response: Response): Promise<T> {
  const body: unknown = await response.json().catch(() => null);
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
    throw new Error("Respuesta inesperada del servidor");
  }
  return (body as { data: T }).data;
}

// GET /api/admin/variants?idProducto=...&pagina=...&tamanoPagina=...
export async function getAdminVariants(
  idProducto: number,
  pagina: number,
  signal?: AbortSignal
): Promise<AdminVariantsResult> {
  const params = new URLSearchParams({
    idProducto: String(idProducto),
    pagina: String(pagina),
    tamanoPagina: "10"
  });
  const response = await authorizedFetch(
    `/admin/variants?${params.toString()}`,
    { signal }
  );
  return readData<AdminVariantsResult>(response);
}

// POST /api/admin/variants
export async function createAdminVariant(
  input: CreateAdminVariantInput
): Promise<CreatedAdminVariant> {
  const response = await authorizedFetch("/admin/variants", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input)
  });
  return readData<CreatedAdminVariant>(response);
}

// PATCH /api/admin/variants/:id/status
export async function changeAdminVariantStatus(
  idVariante: number,
  activa: boolean
): Promise<ChangedVariantStatus> {
  const response = await authorizedFetch(
    `/admin/variants/${idVariante}/status`,
    {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ activa })
    }
  );
  return readData<ChangedVariantStatus>(response);
}
