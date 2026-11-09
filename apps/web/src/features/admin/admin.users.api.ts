import {
  authorizedFetch,
  type Role
} from "../../lib/auth";

// ==========================================
// MODELO DE USUARIO ADMINISTRATIVO
// ==========================================

export interface AdminUser {
  idUsuario: number;
  correo: string;
  rol: Role;
  activo: boolean;
  fechaCreacion: string;
}

// ==========================================
// PAGINACION
// ==========================================

export interface UsersPagination {
  pagina: number;
  tamanoPagina: number;
  totalRegistros: number;
  totalPaginas: number;
}

export interface AdminUsersResponse {
  items: AdminUser[];
  pagination: UsersPagination;
}

// ==========================================
// FILTROS DEL LISTADO
// ==========================================

export interface AdminUsersFilters {
  pagina?: number;
  tamanoPagina?: number;
  busqueda?: string;
  rol?: Role | null;
  activo?: boolean | null;
}

// ==========================================
// DATOS PARA CREAR USUARIO
// ==========================================

export interface CreateAdminUserInput {
  correo: string;
  password: string;
  rol: Role;
}

// ==========================================
// MANEJO CENTRALIZADO DE RESPUESTAS
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
// GET /api/admin/users
// LISTADO CON FILTROS Y PAGINACION
// ==========================================

export async function getAdminUsers(
  filters: AdminUsersFilters = {},
  signal?: AbortSignal
): Promise<AdminUsersResponse> {
  const params = new URLSearchParams();

  params.set(
    "pagina",
    String(filters.pagina ?? 1)
  );

  params.set(
    "tamanoPagina",
    String(filters.tamanoPagina ?? 10)
  );

  const busqueda = filters.busqueda?.trim();

  if (busqueda) {
    params.set("busqueda", busqueda);
  }

  if (filters.rol) {
    params.set("rol", filters.rol);
  }

  if (
    filters.activo !== null &&
    filters.activo !== undefined
  ) {
    params.set(
      "activo",
      filters.activo ? "1" : "0"
    );
  }

  const response = await authorizedFetch(
    `/admin/users?${params.toString()}`,
    { signal }
  );

  return readData<AdminUsersResponse>(
    response
  );
}

// ==========================================
// POST /api/admin/users
// CREAR USUARIO
// ==========================================

export async function createAdminUser(
  input: CreateAdminUserInput
): Promise<AdminUser> {
  const response = await authorizedFetch(
    "/admin/users",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(input)
    }
  );

  return readData<AdminUser>(response);
}

// ==========================================
// PATCH /api/admin/users/:id/role
// CAMBIAR ROL
// ==========================================

export async function changeAdminUserRole(
  idUsuario: number,
  rol: Role
): Promise<AdminUser> {
  const response = await authorizedFetch(
    `/admin/users/${idUsuario}/role`,
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ rol })
    }
  );

  return readData<AdminUser>(response);
}

// ==========================================
// PATCH /api/admin/users/:id/status
// ACTIVAR O DESACTIVAR
// ==========================================

export async function changeAdminUserStatus(
  idUsuario: number,
  activo: boolean
): Promise<AdminUser> {
  const response = await authorizedFetch(
    `/admin/users/${idUsuario}/status`,
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ activo })
    }
  );

  return readData<AdminUser>(response);
}
