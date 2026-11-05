export type Role =
  | "Cliente"
  | "Operador"
  | "Administrador";

export interface AuthUser {
  id: number;
  correo: string;
  rol: Role;
}

export interface AuthSession {
  accessToken: string;
  tokenType: "Bearer";
  expiresIn: number;
  user: AuthUser;
}

interface LoginInput {
  correo: string;
  password: string;
}

// ==========================================
// ESTADO EN MEMORIA
// ==========================================

let currentSession: AuthSession | null = null;

const listeners = new Set<() => void>();

export function getSession(): AuthSession | null {
  return currentSession;
}

export function subscribeSession(
  listener: () => void
): () => void {
  listeners.add(listener);

  return () => {
    listeners.delete(listener);
  };
}

function setSession(
  session: AuthSession | null
): void {
  currentSession = session;

  for (const listener of listeners) {
    listener();
  }
}

// ==========================================
// ERRORES HTTP
// ==========================================

async function errorFromResponse(
  response: Response
): Promise<Error> {
  let message = `Error HTTP ${response.status}`;

  try {
    const data = (await response.json()) as {
      message?: string;
    };

    if (typeof data.message === "string") {
      message = data.message;
    }
  } catch {
    // Respuesta sin JSON.
  }

  return new Error(message);
}

// ==========================================
// LOGIN
// ==========================================

export async function loginRequest(
  input: LoginInput
): Promise<AuthSession> {
  const response = await fetch("/api/auth/login", {
    method: "POST",
    credentials: "include",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(input)
  });

  if (!response.ok) {
    throw await errorFromResponse(response);
  }

  const session =
    (await response.json()) as AuthSession;

  setSession(session);

  return session;
}

// ==========================================
// REFRESH TOKEN CON CONTROL DE CONCURRENCIA
// ==========================================

let refreshPromise: Promise<AuthSession | null> | null =
  null;

export function refreshSession(): Promise<AuthSession | null> {
  if (refreshPromise) {
    return refreshPromise;
  }

  refreshPromise = (async () => {
    const response = await fetch("/api/auth/refresh", {
      method: "POST",
      credentials: "include"
    });

    if (response.status === 401) {
      setSession(null);
      return null;
    }

    if (!response.ok) {
      throw await errorFromResponse(response);
    }

    const session =
      (await response.json()) as AuthSession;

    setSession(session);

    return session;
  })().finally(() => {
    refreshPromise = null;
  });

  return refreshPromise;
}

// ==========================================
// PETICIONES AUTENTICADAS
// ==========================================

export async function authorizedFetch(
  path: string,
  options: RequestInit = {}
): Promise<Response> {
  if (!path.startsWith("/") || path.startsWith("//")) {
    throw new Error("Ruta de API invalida");
  }

  const session =
    getSession() ?? await refreshSession();

  if (!session) {
    throw new Error("Debes iniciar sesion");
  }

  async function send(token: string): Promise<Response> {
    const headers = new Headers(options.headers);

    headers.set("Authorization", `Bearer ${token}`);

    return fetch(`/api${path}`, {
      ...options,
      credentials: "include",
      headers
    });
  }

  const response = await send(session.accessToken);

  if (response.status !== 401) {
    return response;
  }

  // Si otra peticion ya renovó el token,
  // reutilizar el nuevo token en memoria.
  const latest = getSession();

  const renewed =
    latest &&
    latest.accessToken !== session.accessToken
      ? latest
      : await refreshSession();

  if (!renewed) {
    throw new Error("La sesion ha expirado");
  }

  // Un solo reintento: evita bucles infinitos.
  return send(renewed.accessToken);
}

// ==========================================
// LOGOUT
// ==========================================

export async function logoutRequest(): Promise<void> {
  // Esperar una renovación que esté en curso.
  if (refreshPromise) {
    await refreshPromise.catch(() => null);
  }

  const response = await fetch("/api/auth/logout", {
    method: "POST",
    credentials: "include"
  });

  if (!response.ok) {
    throw await errorFromResponse(response);
  }

  setSession(null);
}

// ==========================================
// RUTA INICIAL SEGUN ROL
// ==========================================

export function homeForRole(role: Role): string {
  switch (role) {
    case "Administrador":
      return "/administracion";

    case "Operador":
      return "/operacion";

    case "Cliente":
      return "/mi-cuenta";
  }
}
