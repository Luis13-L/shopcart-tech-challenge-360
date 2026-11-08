import { authorizedFetch } from "../../lib/auth";

// ==========================================
// TIPOS DE DESCUENTO
// ==========================================

export type DiscountType =
  | "PORCENTAJE"
  | "MONTO_FIJO";

// ==========================================
// MODELO DE CUPON
// ==========================================

export interface AdminCoupon {
  idCupon: number;
  codigo: string;
  tipoDescuento: DiscountType;
  valor: string;
  montoMinimo: string;
  limiteUsos: number;
  usosRealizados: number;
  limitePorCliente: number;
  fechaInicio: string;
  fechaFin: string;
  activo: boolean;
  idCategoriaAplicable: number | null;
  fechaCreacion?: string;
}

// ==========================================
// DATOS PARA CREAR O EDITAR
// ==========================================

export interface CouponInput {
  codigo: string;
  tipoDescuento: DiscountType;
  valor: number;
  montoMinimo: number;
  limiteUsos: number;
  limitePorCliente: number;
  fechaInicio: string;
  fechaFin: string;
  activo: boolean;
}

// ==========================================
// PROCESAR RESPUESTA DE API
// ==========================================

async function readData<T>(
  response: Response
): Promise<T> {
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

  return (body as { data: T }).data;
}

// ==========================================
// GET — LISTAR CUPONES
// ==========================================

export async function getAdminCoupons(
  signal?: AbortSignal
): Promise<AdminCoupon[]> {
  const response = await authorizedFetch(
    "/coupons",
    { signal }
  );

  return readData<AdminCoupon[]>(response);
}

// ==========================================
// POST — CREAR CUPON
// ==========================================

export async function createAdminCoupon(
  input: CouponInput
): Promise<AdminCoupon> {
  const response = await authorizedFetch(
    "/coupons",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(input)
    }
  );

  return readData<AdminCoupon>(response);
}

// ==========================================
// PUT — ACTUALIZAR CUPON
// ==========================================

export async function updateAdminCoupon(
  id: number,
  input: CouponInput
): Promise<AdminCoupon> {
  const response = await authorizedFetch(
    `/coupons/${id}`,
    {
      method: "PUT",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(input)
    }
  );

  return readData<AdminCoupon>(response);
}

// ==========================================
// PATCH — ACTIVAR / DESACTIVAR
// ==========================================

export async function changeCouponStatus(
  id: number,
  activo: boolean
): Promise<void> {
  const response = await authorizedFetch(
    `/coupons/${id}/status`,
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ activo })
    }
  );

  await readData<unknown>(response);
}

// ==========================================
// PATCH — ASIGNAR CATEGORIA
// ==========================================

export async function assignCouponCategory(
  id: number,
  idCategoria: number | null
): Promise<AdminCoupon> {
  const response = await authorizedFetch(
    `/coupons/${id}/category`,
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ idCategoria })
    }
  );

  return readData<AdminCoupon>(response);
}
