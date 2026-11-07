import { authorizedFetch } from "../../lib/auth";

export interface ReturnOrderInput {
  idDetallePedido: string;
  cantidad: number;
  motivo: string;
  claveIdempotencia: string;
}

export interface ReturnOrderResult {
  idDevolucion: string;
  idPedido: string;
  idDetallePedido: string;
  cantidad: number;
  montoReembolso: string;
  estadoPedido: string;
  reutilizado: boolean;
}


export class ReturnApiError extends Error {
  public readonly status: number;
  public readonly code?: string;

  constructor(
    message: string,
    status: number,
    code?: string
  ) {
    super(message);

    this.name = "ReturnApiError";
    this.status = status;
    this.code = code;
  }
}


// ==========================================
// POST /api/orders/:id/returns
// ==========================================

export async function requestOrderReturn(
  orderId: string,
  input: ReturnOrderInput
): Promise<ReturnOrderResult> {

  const response = await authorizedFetch(
    `/orders/${encodeURIComponent(orderId)}/returns`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(input)
    }
  );

  const body: unknown = await response
    .json()
    .catch(() => null);

  if (!response.ok) {
    let message = `Error HTTP ${response.status}`;
    let code: string | undefined;

    if (
      body !== null &&
      typeof body === "object"
    ) {
      if (
        "message" in body &&
        typeof body.message === "string"
      ) {
        message = body.message;
      }

      if (
        "code" in body &&
        typeof body.code === "string"
      ) {
        code = body.code;
      }
    }

    throw new ReturnApiError(
      message,
      response.status,
      code
    );
  }

  if (
    body === null ||
    typeof body !== "object" ||
    !("data" in body) ||
    typeof body.data !== "object" ||
    body.data === null
  ) {
    throw new Error(
      "Respuesta inesperada de la API de devoluciones"
    );
  }

  return body.data as ReturnOrderResult;
}
