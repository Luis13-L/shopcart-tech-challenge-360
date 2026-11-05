import { useState, type FormEvent } from "react";

import {
  ArrowRight,
  Eye,
  EyeOff,
  Layers3,
  LockKeyhole,
  Mail,
  ShieldCheck,
  Sparkles
} from "lucide-react";

import {
  Link,
  Navigate,
  useNavigate
} from "react-router";

import { useAuth } from "../auth/AuthProvider";
import { homeForRole } from "../lib/auth";

export function LoginPage() {
  const navigate = useNavigate();

  const { session, ready, signIn } = useAuth();

  const [correo, setCorreo] = useState("");
  const [password, setPassword] = useState("");

  const [showPassword, setShowPassword] =
    useState(false);

  const [loading, setLoading] = useState(false);

  const [error, setError] =
    useState<string | null>(null);

  async function handleSubmit(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    setError(null);
    setLoading(true);

    try {
      const result = await signIn({
        correo: correo.trim(),
        password
      });

      setPassword("");

      navigate(homeForRole(result.user.rol), {
        replace: true
      });
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "No fue posible iniciar sesión"
      );
    } finally {
      setLoading(false);
    }
  }

  if (!ready) {
    return (
      <main className="auth-loading" role="status">
        <span className="auth-spinner" />
        <p>Comprobando sesión...</p>
      </main>
    );
  }

  if (session) {
    return (
      <Navigate
        to={homeForRole(session.user.rol)}
        replace
      />
    );
  }

  return (
    <main className="auth-page">
      <section className="auth-showcase">
        <div className="auth-showcase-inner">

          <Link to="/" className="auth-brand">
            <span className="auth-brand-mark">
              <Layers3 size={24} />
            </span>
            shopcart.
          </Link>

          <div className="auth-showcase-copy">
            <span className="auth-kicker">
              <Sparkles size={16} />
              TU EXPERIENCIA COMIENZA AQUÍ
            </span>

            <h1>
              Bienvenido
              <span> de nuevo.</span>
            </h1>

            <p>
              Tu tienda, tus pedidos y tus
              productos favoritos en un solo lugar.
            </p>

            <div className="auth-showcase-card">
              <ShieldCheck size={25} />

              <div>
                <strong>
                  Acceso protegido
                </strong>

                <small>
                  Sesiones seguras y permisos
                  definidos por rol.
                </small>
              </div>
            </div>
          </div>

          <span className="auth-showcase-footer">
            SHOPCART / TECH CHALLENGE 360
          </span>
        </div>
      </section>

      <section className="auth-form-side">
        <div className="auth-form-shell">

          <Link to="/" className="auth-back">
            ← Volver a la tienda
          </Link>

          <span className="auth-form-eyebrow">
            ACCESO A SHOPCART
          </span>

          <h2>Iniciar sesión</h2>

          <p className="auth-intro">
            Ingresa con tus credenciales para
            continuar.
          </p>

          <form
            onSubmit={handleSubmit}
            className="auth-form"
          >
            <label htmlFor="login-correo">
              Correo electrónico
            </label>

            <div className="auth-input">
              <Mail size={19} />

              <input
                id="login-correo"
                type="email"
                placeholder="correo@ejemplo.com"
                autoComplete="username"
                required
                maxLength={254}
                value={correo}
                onChange={(event) =>
                  setCorreo(event.target.value)
                }
              />
            </div>

            <label htmlFor="login-password">
              Contraseña
            </label>

            <div className="auth-input">
              <LockKeyhole size={19} />

              <input
                id="login-password"
                type={
                  showPassword
                    ? "text"
                    : "password"
                }
                placeholder="Tu contraseña"
                autoComplete="current-password"
                required
                value={password}
                onChange={(event) =>
                  setPassword(event.target.value)
                }
              />

              <button
                type="button"
                className="auth-password-toggle"
                aria-label={
                  showPassword
                    ? "Ocultar contraseña"
                    : "Mostrar contraseña"
                }
                aria-pressed={showPassword}
                onClick={() =>
                  setShowPassword((value) => !value)
                }
              >
                {showPassword ? (
                  <EyeOff size={19} />
                ) : (
                  <Eye size={19} />
                )}
              </button>
            </div>

            {error && (
              <div
                className="auth-error"
                role="alert"
              >
                {error}
              </div>
            )}

            <button
              className="auth-submit"
              type="submit"
              disabled={loading}
            >
              {loading
                ? "Validando credenciales..."
                : "Ingresar a ShopCart"}

              {!loading && <ArrowRight size={19} />}
            </button>

          </form>

          <p className="auth-form-note">
            ¿Todavía no tienes cuenta?
            El registro de clientes se integrará
            en el siguiente paso.
          </p>
        </div>
      </section>
    </main>
  );
}
