import { authorizedFetch } from "../../lib/auth";

export interface Address {
  idDireccion: number;
  destinatario: string;
  telefono: string;
  departamento: string;
  municipio: string;
  direccionLinea1: string;
  referencia: string | null;
  activa: boolean;
  fechaCreacion: string;
}

export interface CreateAddressInput {
  destinatario: string;
  telefono: string;
  departamento: string;
  municipio: string;
  direccionLinea1: string;
  referencia: string | null;
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
    throw new Error("Respuesta inesperada de la API");
  }

  return (body as ApiResponse<T>).data;
}

// GET /api/addresses
export async function listMyAddresses(): Promise<Address[]> {
  const response = await authorizedFetch("/addresses");
  return readData<Address[]>(response);
}

// POST /api/addresses
export async function createMyAddress(
  input: CreateAddressInput
): Promise<Address> {
  const response = await authorizedFetch("/addresses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(input)
  });

  return readData<Address>(response);
}
