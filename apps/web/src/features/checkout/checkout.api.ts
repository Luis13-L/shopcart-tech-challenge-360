import { authorizedFetch } from "../../lib/auth";

// ==========================================
// RESERVA DE INVENTARIO
// ==========================================

export interface InventoryReservation {
  idReserva: string;
  idCarrito: string;
}

// ==========================================
// RESULTADO DEL CHECKOUT
// ==========================================

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

// ==========================================
// DATOS PARA CONFIRMAR COMPRA
// ==========================================

export interface ConfirmCheckoutInput {
  idReserva: string;
  idDireccion: number;
  claveIdempotencia: string;

  // Subtotal sin descontar cupones.
  totalEsperado: string;

  // Opcional para conservar compatibilidad
  // con pedidos sin promocion.
  codigoCupon?: string;
}

// ==========================================
// RESPUESTA ESTANDAR DE LA API
// ==========================================

interface ApiResponse<T> {
  data: T;
  message?: string;
}

// ==========================================
// PROCESAR RESPUESTAS HTTP
// ==========================================

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
      "La API devolvio una respuesta inesperada"
    );
  }

  return (body as ApiResponse<T>).data;
}

// ==========================================
// POST /api/checkout/reservations
// RESERVAR INVENTARIO
// ==========================================

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

  return readData<InventoryReservation>(
    response
  );
}

// ==========================================
// POST /api/checkout/confirm
// CONFIRMAR COMPRA CON O SIN CUPON
// ==========================================

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

  return readData<CheckoutResult>(
    response
  );
}

// ==========================================
// PASO 75B.4 - COTIZACION DE CUPONES
// ==========================================

export interface CouponQuote {
  idCarrito: string;
  codigoCupon: string;
  tipoDescuento: "PORCENTAJE" | "MONTO_FIJO";
  valor: string;
  idCategoriaAplicable: number | null;
  subtotal: string;
  subtotalElegible: string;
  descuento: string;
  total: string;
}

export interface QuoteCheckoutInput {
  idCarrito: string;
  codigoCupon: string;
}

// POST /api/checkout/quote
export async function quoteCheckout(
  input: QuoteCheckoutInput
): Promise<CouponQuote> {
  const response = await authorizedFetch(
    "/checkout/quote",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(input)
    }
  );

  return readData<CouponQuote>(response);
}
