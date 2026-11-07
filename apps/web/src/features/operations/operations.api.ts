import { authorizedFetch } from "../../lib/auth";
import type { OrderStatus } from "../orders/orders.api";

export type NextOrderStatus =
  | "PREPARANDO"
  | "DESPACHADO"
  | "ENTREGADO";

export interface OperatorOrder {
  idPedido: string;
  idUsuario: number;
  estado: OrderStatus;
  subtotal: string;
  descuento: string;
  total: string;
  codigoCupon: string | null;
  montoDevuelto: string;
  ventaNeta: string;
  fechaCreacion: string;
  fechaActualizacion: string;
}

export interface OperatorOrdersResult {
  items: OperatorOrder[];
  pagination: {
    pagina: number;
    tamanoPagina: number;
    totalRegistros: number;
    totalPaginas: number;
  };
}

export interface OperatorOrdersFilters {
  pagina: number;
  estado?: OrderStatus;
  idCliente?: number;
  fechaInicio?: string;
  fechaFin?: string;
}

export interface ChangeStatusResult {
  idPedido: string;
  estadoAnterior: string;
  estadoNuevo: string;
  fechaCambio: string;
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

// GET /api/orders
export async function listOperatorOrders(
  filters: OperatorOrdersFilters,
  signal?: AbortSignal
): Promise<OperatorOrdersResult> {

  const params = new URLSearchParams({
    pagina: String(filters.pagina),
    tamanoPagina: "10"
  });

  if (filters.estado) {
    params.set("estado", filters.estado);
  }

  if (filters.idCliente) {
    params.set(
      "idCliente",
      String(filters.idCliente)
    );
  }

  if (filters.fechaInicio) {
    params.set(
      "fechaInicio",
      filters.fechaInicio
    );
  }

  if (filters.fechaFin) {
    params.set(
      "fechaFin",
      filters.fechaFin
    );
  }

  const response = await authorizedFetch(
    `/orders?${params.toString()}`,
    { signal }
  );

  return readData<OperatorOrdersResult>(
    response
  );
}

// PATCH /api/orders/:id/status
export async function advanceOrderStatus(
  orderId: string,
  estadoNuevo: NextOrderStatus,
  observacion?: string
): Promise<ChangeStatusResult> {

  const response = await authorizedFetch(
    `/orders/${encodeURIComponent(orderId)}/status`,
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        estadoNuevo,
        ...(observacion?.trim()
          ? { observacion: observacion.trim() }
          : {})
      })
    }
  );

  return readData<ChangeStatusResult>(
    response
  );
}

export function nextOrderStatus(
  status: OrderStatus
): NextOrderStatus | null {
  switch (status) {
    case "PAGADO":
      return "PREPARANDO";

    case "PREPARANDO":
      return "DESPACHADO";

    case "DESPACHADO":
      return "ENTREGADO";

    default:
      return null;
  }
}
