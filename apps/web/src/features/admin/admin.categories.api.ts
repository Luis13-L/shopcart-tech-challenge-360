import { authorizedFetch } from "../../lib/auth";

export interface AdminCategory {
  idCategoria: number;
  nombre: string;
  descripcion: string | null;
  activa: boolean;
  fechaCreacion?: string;
}

export interface CategoryInput {
  nombre: string;
  descripcion: string | null;
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

// GET /api/catalog/categories/admin
export async function getAdminCategories(
  signal?: AbortSignal
): Promise<AdminCategory[]> {
  const response = await authorizedFetch(
    "/catalog/categories/admin",
    { signal }
  );

  return readData<AdminCategory[]>(response);
}

// POST /api/catalog/categories
export async function createAdminCategory(
  input: CategoryInput
): Promise<AdminCategory> {
  const response = await authorizedFetch(
    "/catalog/categories",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(input)
    }
  );

  return readData<AdminCategory>(response);
}

// PATCH /api/catalog/categories/:id
export async function updateAdminCategory(
  id: number,
  input: CategoryInput
): Promise<AdminCategory> {
  const response = await authorizedFetch(
    `/catalog/categories/${id}`,
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(input)
    }
  );

  return readData<AdminCategory>(response);
}

// PATCH /api/catalog/categories/:id/status
export async function changeCategoryStatus(
  id: number,
  activa: boolean
): Promise<AdminCategory> {
  const response = await authorizedFetch(
    `/catalog/categories/${id}/status`,
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ activa })
    }
  );

  return readData<AdminCategory>(response);
}
