import { useState } from "react";
import {
  ArrowLeft,
  LayoutDashboard,
  LogOut,
  ShieldCheck,
  UserRound
} from "lucide-react";

import {
  Link,
  useNavigate
} from "react-router";

import { useAuth } from "../auth/AuthProvider";

import {
  type Role
} from "../lib/auth";

const descriptions: Record<Role, string> = {
  Cliente:
    "Desde aquí podrás administrar tus compras, direcciones y devoluciones.",

  Operador:
    "Este espacio reunirá la gestión de pedidos y los movimientos de inventario.",

  Administrador:
    "Aquí integraremos catálogo, inventario, promociones, reportes y auditoría."
};

export function WorkspacePage() {
  const { session, signOut } = useAuth();

  const navigate = useNavigate();

  const [loading, setLoading] = useState(false);

  const [error, setError] =
    useState<string | null>(null);

  const user = session?.user;

  async function handleLogout() {
    setError(null);
    setLoading(true);

    try {
      await signOut();
      navigate("/", { replace: true });
    } catch {
      setError(
        "No fue posible cerrar la sesión. Inténtalo nuevamente."
      );
    } finally {
      setLoading(false);
    }
  }

  if (!user) {
    return null;
  }

  return (
    <main className="workspace-page">
      <div className="workspace-container">

        <header className="workspace-topbar">
          <Link to="/" className="workspace-home">
            <ArrowLeft size={17} />
            Volver a ShopCart
          </Link>

          <button
            type="button"
            onClick={() => {
              void handleLogout();
            }}
            disabled={loading}
            className="workspace-logout"
          >
            <LogOut size={17} />
            {loading
              ? "Cerrando..."
              : "Cerrar sesión"}
          </button>
        </header>

        <div className="workspace-card">

          <div className="workspace-icon">
            <LayoutDashboard size={28} />
          </div>

          <span className="workspace-eyebrow">
            SESIÓN ACTIVA
          </span>

          <h1>
            Bienvenido a tu espacio.
          </h1>

          <p className="workspace-description">
            {descriptions[user.rol]}
          </p>

          <div className="workspace-identity">
            <UserRound size={21} />

            <div>
              <strong>{user.correo}</strong>
              <small>Rol: {user.rol}</small>
            </div>

            <ShieldCheck size={21} />
          </div>
          {user.rol === "Cliente" && (
            <Link
              to="/mis-pedidos"
              className="btn btn-primary"
            >
              <LayoutDashboard size={18} />
              Consultar mis pedidos
            </Link>
          )}
          
          {(
            user.rol === "Operador" ||
            user.rol === "Administrador"
          ) && (
            <Link
              to="/operacion/pedidos"
              className="btn btn-primary"
            >
              <LayoutDashboard size={18} />
              Gestionar pedidos
            </Link>
          )}
          {(
            user.rol === "Operador" ||
            user.rol === "Administrador"
          ) && (
            <Link
              to="/operacion/inventario"
              className="btn btn-primary"
            >
              <LayoutDashboard size={18} />
              Inventario y Kardex
            </Link>
          )}
          {user.rol === "Administrador" && (
            <Link
              to="/administracion/categorias"
              className="btn btn-primary"
            >
              <LayoutDashboard size={18} />
              Administrar categorías
            </Link>
          )}
          {user.rol === "Administrador" && (
            <Link
              to="/administracion/productos"
              className="btn btn-primary"
            >
              <LayoutDashboard size={18} />
              Administrar productos
            </Link>
          )}
          <p className="workspace-notice">
            Este es el punto de entrada autenticado.
            Las operaciones específicas se incorporarán
            como páginas independientes.
          </p>

          {error && (
            <p className="auth-error" role="alert">
              {error}
            </p>
          )}

        </div>
      </div>
    </main>
  );
}
