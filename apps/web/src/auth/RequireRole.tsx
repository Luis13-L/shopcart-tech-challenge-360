import {
  Link,
  Navigate,
  Outlet,
  useLocation
} from "react-router";

import { ShieldAlert } from "lucide-react";

import { useAuth } from "./AuthProvider";
import type { Role } from "../lib/auth";

interface RequireRoleProps {
  allowed: Role[];
}

export function RequireRole({
  allowed
}: RequireRoleProps) {
  const { session, ready } = useAuth();

  const location = useLocation();

  if (!ready) {
    return (
      <main className="auth-loading" role="status">
        <span className="auth-spinner" />
        <p>Comprobando sesión...</p>
      </main>
    );
  }

  if (!session) {
    return (
      <Navigate
        to="/login"
        replace
        state={{
          from: location.pathname
        }}
      />
    );
  }

  if (!allowed.includes(session.user.rol)) {
    return (
      <main className="auth-denied">
        <ShieldAlert size={46} />

        <h1>Acceso restringido</h1>

        <p>
          Tu cuenta no tiene permisos para
          consultar esta sección.
        </p>

        <Link className="btn btn-primary" to="/">
          Volver a la tienda
        </Link>
      </main>
    );
  }

  return <Outlet />;
}
