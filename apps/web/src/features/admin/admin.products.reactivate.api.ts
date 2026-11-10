import {
  authorizedFetch
} from "../../lib/auth";

export interface ReactivatedProduct {
  idProducto: number;
  nombre: string;
  activo: boolean;
  variantesReactivadas: number;
  reutilizado: boolean;
}

// PATCH /api/admin/products/:id/reactivate
export async function reactivateAdminProduct(
  idProducto: number
): Promise<ReactivatedProduct> {
  if (
    !Number.isSafeInteger(idProducto) ||
    idProducto <= 0 ||
    idProducto > 2147483647
  ) {
    throw new Error("ID de producto invalido");
  }

  const response = await authorizedFetch(
    `/admin/products/${idProducto}/reactivate`,
    { method: "PATCH" }
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
    throw new Error("Respuesta inesperada del servidor");
  }

  return (body as { data: ReactivatedProduct }).data;
}
