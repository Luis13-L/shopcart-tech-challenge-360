import { authorizedFetch } from "../../lib/auth";

export interface CreateProductInput {
  idCategoria: number;
  nombre: string;
  descripcion?: string;
  sku: string;
  precioActual: string;
  imagen?: File;
}

export interface UpdateProductInput {
  idCategoria?: number;
  nombre?: string;
  descripcion?: string | null;
}

export interface CreatedProduct {
  idProducto: number;
  idVariante: number;
  nombre: string;
  sku: string;
  precioActual: string;
}

export interface PriceUpdate {
  idVariante: number;
  idProducto: number;
  sku: string;
  precioAnterior: string;
  precioActual: string;
  actualizado: boolean;
  fechaCambio: string | null;
}

async function send<T>(
  path: string,
  method: "POST" | "PATCH",
  data?: unknown
): Promise<T> {
  const response = await authorizedFetch(path, {
    method,
    headers: {
      "Content-Type": "application/json"
    },
    body: data === undefined
      ? undefined
      : JSON.stringify(data)
  });

  const body: unknown = await response
    .json()
    .catch(() => null);

  if (!response.ok) {
    let message = `Error HTTP ${response.status}`;

    if (
      body &&
      typeof body === "object" &&
      "message" in body &&
      typeof body.message === "string"
    ) {
      message = body.message;
    }

    throw new Error(message);
  }

  if (
    !body ||
    typeof body !== "object" ||
    !("data" in body)
  ) {
    throw new Error(
      "El servidor no devolvió datos válidos"
    );
  }

  return (body as { data: T }).data;
}

export async function createAdminProduct(
  input: CreateProductInput
): Promise<CreatedProduct> {

  if (!input.imagen) {
    return send<CreatedProduct>(
      "/catalog/products",
      "POST",
      input
    );
  }

  const form = new FormData();

  form.append(
    "idCategoria",
    String(input.idCategoria)
  );

  form.append("nombre", input.nombre);
  form.append(
    "descripcion",
    input.descripcion ?? ""
  );
  form.append("sku", input.sku);
  form.append("precioActual", input.precioActual);
  form.append("imagen", input.imagen);

  const response = await authorizedFetch(
    "/catalog/products/with-image",
    {
      method: "POST",
      body: form
    }
  );

  // No establecer Content-Type manualmente.
  // El navegador añade el boundary de FormData.
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

  return (body as { data: CreatedProduct }).data;
}

export function updateAdminProduct(
  idProducto: number,
  input: UpdateProductInput
): Promise<{
  idProducto: number;
  nombre: string;
  idCategoria: number;
  descripcion: string | null;
  activo: boolean;
}> {
  return send(
    `/catalog/products/${idProducto}`,
    "PATCH",
    input
  );
}

export function deactivateAdminProduct(
  idProducto: number
): Promise<{
  idProducto: number;
  nombre: string;
  activo: boolean;
  variantesDesactivadas: number;
}> {
  return send(
    `/catalog/products/${idProducto}/status`,
    "PATCH"
  );
}

export function changeVariantPrice(
  idVariante: number,
  precioNuevo: string,
  motivo: string
): Promise<PriceUpdate> {
  return send<PriceUpdate>(
    `/catalog/variants/${idVariante}/price`,
    "PATCH",
    { precioNuevo, motivo }
  );
}
