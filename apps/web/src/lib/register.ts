export interface RegisterInput {
  correo: string;
  password: string;
}

export interface RegisteredUser {
  id: number;
  correo: string;
  rol: "Cliente";
  fechaCreacion: string;
}

export interface RegisterResponse {
  message: string;
  data: RegisteredUser;
}

// ==========================================
// REGISTRAR CLIENTE
// POST /api/auth/register
// ==========================================

export async function registerCustomer(
  input: RegisterInput
): Promise<RegisterResponse> {

  const response = await fetch("/api/auth/register", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json"
    },
    body: JSON.stringify({
      correo: input.correo.trim().toLowerCase(),
      password: input.password
    })
  });

  const result: unknown = await response
    .json()
    .catch(() => null);

  if (!response.ok) {
    let message = "No fue posible crear la cuenta";

    if (
      typeof result === "object" &&
      result !== null &&
      "message" in result &&
      typeof result.message === "string"
    ) {
      message = result.message;
    }

    throw new Error(message);
  }

  if (
    typeof result !== "object" ||
    result === null ||
    !("data" in result) ||
    typeof result.data !== "object" ||
    result.data === null
  ) {
    throw new Error(
      "La API devolvio una respuesta inesperada"
    );
  }

  return result as RegisterResponse;
}
