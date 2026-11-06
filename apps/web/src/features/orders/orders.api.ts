import { authorizedFetch } from "../../lib/auth";

export type OrderStatus =
  | "PAGADO"
  | "PREPARANDO"
  | "DESPACHADO"
  | "ENTREGADO"
  | "CANCELADO"
  | "DEVUELTO_PARCIAL"
  | "DEVUELTO_TOTAL";

export interface Order {
  idPedido: string;
  estado: OrderStatus;
  subtotal: string;
  descuento: string;
  total: string;
  codigoCupon: string | null;
  fechaCreacion: string;
  fechaActualizacion: string;
}

export interface OrderItem {
  idDetallePedido: string;
  idVariante: number;
  sku: string;
  nombreProducto: string;
  precioUnitario: string;
  cantidad: number;
  cantidadDevuelta: number;
  importeLinea: string;
}

export interface OrderHistory {
  idHistorialPedido: string;
  estadoAnterior: string | null;
  estadoNuevo: string;
  observacion: string | null;
  fechaCambio: string;
}

export interface OrderDetail extends Order {
  direccionEntrega: {
    destinatario: string;
    telefono: string;
    departamento: string;
    municipio: string;
    direccionLinea1: string;
    referencia: string | null;
  };
  productos: OrderItem[];
  historial: OrderHistory[];
}

export interface OrdersResult {
  items: Order[];
  pagination: {
    pagina: number;
    tamanoPagina: number;
    totalRegistros: number;
    totalPaginas: number;
  };
}

export interface CancelResult {
  idPedido: string;
  estadoAnterior: string;
  estadoNuevo: string;
  yaCancelado: boolean;
  fechaCambio: string | null;
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

// GET /api/orders/my
export async function getMyOrders(
  page: number,
  status: OrderStatus | "",
  signal?: AbortSignal
): Promise<OrdersResult> {
  const params = new URLSearchParams({
    pagina: String(page),
    tamanoPagina: "10"
  });

  if (status !== "") {
    params.set("estado", status);
  }

  const response = await authorizedFetch(
    `/orders/my?${params.toString()}`,
    { signal }
  );

  return readData<OrdersResult>(response);
}

// GET /api/orders/my/:id
export async function getMyOrder(
  id: string,
  signal?: AbortSignal
): Promise<OrderDetail> {
  const response = await authorizedFetch(
    `/orders/my/${encodeURIComponent(id)}`,
    { signal }
  );

  return readData<OrderDetail>(response);
}

// POST /api/orders/:id/cancel
export async function cancelMyOrder(
  id: string,
  reason: string
): Promise<CancelResult> {
  const response = await authorizedFetch(
    `/orders/${encodeURIComponent(id)}/cancel`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        motivo: reason.trim()
      })
    }
  );

  return readData<CancelResult>(response);
}

export function formatOrderDate(
  value: string
): string {
  return new Intl.DateTimeFormat("es-GT", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "America/Guatemala"
  }).format(new Date(value));
}

export function orderStatusLabel(
  status: string
): string {
  const labels: Record<string, string> = {
    PAGADO: "Pagado",
    PREPARANDO: "Preparando",
    DESPACHADO: "Despachado",
    ENTREGADO: "Entregado",
    CANCELADO: "Cancelado",
    DEVUELTO_PARCIAL: "Devolución parcial",
    DEVUELTO_TOTAL: "Devolución total"
  };

  return labels[status] ?? status;
}
