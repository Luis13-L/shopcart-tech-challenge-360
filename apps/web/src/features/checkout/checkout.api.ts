import { authorizedFetch } from "../../lib/auth";

export interface InventoryReservation {
  idReserva: string;
  idCarrito: string;
}

export interface CheckoutResult {
  idPedido: string;
  idCarrito: string;
  idReserva: string;
  estado: string;
  subtotal: string;
  descuento: string;
  total: string;
  reutilizado: boolean;
}

export interface ConfirmCheckoutInput {
  idReserva: string;
  idDireccion: number;
  claveIdempotencia: string;
  totalEsperado: string;
}

interface ApiResponse<T> {
  data: T;
  message?: string;
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
      "La API devolvio una respuesta inesperada"
    );
  }

  return (body as ApiResponse<T>).data;
}

// POST /api/checkout/reservations
export async function reserveCheckout(
  cartId: string
): Promise<InventoryReservation> {
  const response = await authorizedFetch(
    "/checkout/reservations",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        idCarrito: cartId
      })
    }
  );

  return readData<InventoryReservation>(response);
}

// POST /api/checkout/confirm
export async function confirmCheckout(
  input: ConfirmCheckoutInput
): Promise<CheckoutResult> {
  const response = await authorizedFetch(
    "/checkout/confirm",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(input)
    }
  );

  return readData<CheckoutResult>(response);
}
