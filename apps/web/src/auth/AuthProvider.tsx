import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  useSyncExternalStore,
  type ReactNode
} from "react";

import {
  getSession,
  subscribeSession,
  refreshSession,
  loginRequest,
  logoutRequest,
  type AuthSession
} from "../lib/auth";

interface AuthContextValue {
  session: AuthSession | null;
  ready: boolean;

  signIn: typeof loginRequest;
  signOut: typeof logoutRequest;
}

const AuthContext =
  createContext<AuthContextValue | null>(null);

export function AuthProvider({
  children
}: {
  children: ReactNode;
}) {
  const session = useSyncExternalStore(
    subscribeSession,
    getSession,
    getSession
  );

  const [ready, setReady] = useState(false);

  useEffect(() => {
    let active = true;

    // Al recargar la pagina no hay access token
    // en memoria. Intentamos recuperar la sesion
    // con la cookie HttpOnly.
    refreshSession()
      .catch((error: unknown) => {
        console.warn(
          "No se pudo restaurar la sesion:",
          error
        );
      })
      .finally(() => {
        if (active) {
          setReady(true);
        }
      });

    return () => {
      active = false;
    };
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({
      session,
      ready,
      signIn: loginRequest,
      signOut: logoutRequest
    }),
    [session, ready]
  );

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);

  if (!context) {
    throw new Error(
      "useAuth debe utilizarse dentro de AuthProvider"
    );
  }

  return context;
}
