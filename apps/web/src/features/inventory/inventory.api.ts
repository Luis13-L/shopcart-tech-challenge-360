import { authorizedFetch } from "../../lib/auth";

export type ManualMovementType =
  | "ENTRADA"
  | "AJUSTE_POSITIVO"
  | "AJUSTE_NEGATIVO";

export interface InventoryStock {
  idVariante: number;
  sku: string;
  cantidadFisica: number;
  cantidadReservada: number;
  cantidadDisponible: number;
  fechaActualizacion: string;
}

export interface InventoryMovement {
  idMovimientoInventario: string;
  idVariante: number;
  idUsuario?: number;
  tipoMovimiento: string;
  cantidadFirmada: number;
  saldoAnterior: number;
  saldoPosterior: number;
  motivo?: string;
  fechaMovimiento: string;
}

export interface InventoryKardex {
  items: InventoryMovement[];
  pagination: {
    pagina: number;
    tamanoPagina: number;
    totalRegistros: number;
    totalPaginas: number;
  };
}

export interface CreateMovementInput {
  idVariante: number;
  tipoMovimiento: ManualMovementType;
  cantidad: number;
  motivo: string;
}

export class InventoryApiError extends Error {
  readonly status: number;

  constructor(
    message: string,
    status: number
  ) {
    super(message);
    this.name = "InventoryApiError";
    this.status = status;
  }
}

async function readData<T>(
  response: Response
): Promise<T> {
  const body: unknown = await response
    .json()
    .catch(() => null);

  if (!response.ok) {
    let message = `Error HTTP ${response.status}`;

    if (
      body !== null &&
      typeof body === "object" &&
      "message" in body &&
      typeof body.message === "string"
    ) {
      message = body.message;
    }

    throw new InventoryApiError(
      message,
      response.status
    );
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

// GET /api/inventory/variants/:id
export async function getInventoryStock(
  variantId: number,
  signal?: AbortSignal
): Promise<InventoryStock> {

  const response = await authorizedFetch(
    `/inventory/variants/${variantId}`,
    { signal }
  );

  return readData<InventoryStock>(response);
}

// GET /api/inventory/variants/:id/movements
export async function getInventoryKardex(
  variantId: number,
  page: number,
  signal?: AbortSignal
): Promise<InventoryKardex> {

  const params = new URLSearchParams({
    pagina: String(page),
    tamanoPagina: "10"
  });

  const response = await authorizedFetch(
    `/inventory/variants/${variantId}/movements?${params}`,
    { signal }
  );

  return readData<InventoryKardex>(response);
}

// POST /api/inventory/movements
export async function createInventoryMovement(
  input: CreateMovementInput
): Promise<InventoryMovement> {

  const response = await authorizedFetch(
    "/inventory/movements",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(input)
    }
  );

  return readData<InventoryMovement>(response);
}
