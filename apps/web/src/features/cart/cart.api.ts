import { authorizedFetch } from "../../lib/auth";

// ==========================================
// CONTRATOS DEL BACKEND
// ==========================================

export interface CartItem {
  idDetalleCarrito: string;
  idVariante: number;
  sku: string;
  nombreProducto: string;
  precioUnitario: string;
  cantidad: number;
  importeLinea: string;
}

export interface Cart {
  idCarrito: string;
  cantidadLineas: number;
  subtotal: string;
  descuento: string;
  total: string;
  items: CartItem[];
}

interface ApiResponse<T> {
  data: T;
  message?: string;
}

interface CartIdentity {
  idCarrito: string;
}

// ==========================================
// PROCESAR RESPUESTAS
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
      typeof body === "object" &&
      body !== null &&
      "message" in body &&
      typeof body.message === "string"
    ) {
      message = body.message;
    }

    throw new Error(message);
  }

  if (
    typeof body !== "object" ||
    body === null ||
    !("data" in body)
  ) {
    throw new Error(
      "La API devolvio una respuesta inesperada"
    );
  }

  return (body as ApiResponse<T>).data;
}

// ==========================================
// CREAR O RECUPERAR CARRITO
// ==========================================

export async function ensureCart(): Promise<string> {

  const response = await authorizedFetch("/cart", {
    method: "POST"
  });

  const data = await readData<CartIdentity>(response);

  return data.idCarrito;
}

// ==========================================
// CONSULTAR CARRITO
// ==========================================

export async function fetchCart(
  cartId: string
): Promise<Cart> {

  const response = await authorizedFetch(
    `/cart/${encodeURIComponent(cartId)}`
  );

  return readData<Cart>(response);
}

// ==========================================
// GUARDAR CANTIDAD ABSOLUTA
// ==========================================

export async function saveCartQuantity(
  variantId: number,
  quantity: number
): Promise<Cart> {

  const response = await authorizedFetch(
    "/cart/items",
    {
      method: "PUT",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        idVariante: variantId,
        cantidad: quantity
      })
    }
  );

  return readData<Cart>(response);
}

// ==========================================
// ELIMINAR VARIANTE
// ==========================================

export async function deleteCartVariant(
  variantId: number
): Promise<Cart> {

  const response = await authorizedFetch(
    `/cart/items/${variantId}`,
    {
      method: "DELETE"
    }
  );

  return readData<Cart>(response);
}
