import {
  useState,
  type FormEvent
} from "react";

import {
  ArrowRight,
  CheckCircle2,
  Eye,
  EyeOff,
  Layers3,
  LockKeyhole,
  Mail,
  ShieldCheck,
  Sparkles,
  UserRoundPlus
} from "lucide-react";

import {
  Link,
  Navigate
} from "react-router";

import {
  useAuth
} from "../auth/AuthProvider";

import {
  homeForRole
} from "../lib/auth";

import {
  registerCustomer
} from "../lib/register";

// ==========================================
// PAGINA DE REGISTRO
// ==========================================

export function RegisterPage() {

  const { session, ready } = useAuth();

  const [correo, setCorreo] = useState("");

  const [password, setPassword] = useState("");

  const [confirmPassword, setConfirmPassword] =
    useState("");

  const [showPassword, setShowPassword] =
    useState(false);

  const [loading, setLoading] = useState(false);

  const [error, setError] =
    useState<string | null>(null);

  const [registeredEmail, setRegisteredEmail] =
    useState<string | null>(null);

  // ========================================
  // VALIDAR CONTRASENA
  // ========================================

  function validatePassword(): string | null {

    if (password.length < 12) {
      return "La contraseña requiere al menos 12 caracteres";
    }

    const bytes = new TextEncoder()
      .encode(password)
      .length;

    if (bytes > 72) {
      return "La contraseña no puede superar los 72 bytes";
    }

    if (password !== confirmPassword) {
      return "Las contraseñas no coinciden";
    }

    return null;
  }

  // ========================================
  // PROCESAR REGISTRO
  // ========================================

  async function handleSubmit(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {

    event.preventDefault();

    if (loading) {
      return;
    }

    setError(null);

    const validationError = validatePassword();

    if (validationError) {
      setError(validationError);
      return;
    }

    setLoading(true);

    try {

      const result = await registerCustomer({
        correo,
        password
      });

      // No conservar la contraseña tras el registro.
      setPassword("");
      setConfirmPassword("");

      setRegisteredEmail(
        result.data.correo
      );

    } catch (cause) {

      setError(
        cause instanceof Error
          ? cause.message
          : "Ocurrio un error al registrar la cuenta"
      );

    } finally {

      setLoading(false);

    }
  }

  // ========================================
  // RESTAURACION DE SESION
  // ========================================

  if (!ready) {
    return (
      <main className="auth-loading" role="status">
        <span className="auth-spinner" />
        <p>Comprobando sesión...</p>
      </main>
    );
  }

  // Un usuario autenticado no necesita
  // registrarse nuevamente.
  if (session) {
    return (
      <Navigate
        to={homeForRole(session.user.rol)}
        replace
      />
    );
  }

  // ========================================
  // INTERFAZ
  // ========================================

  return (
    <main className="auth-page">

      {/* PANEL PROMOCIONAL */}

      <section className="auth-showcase">

        <div className="auth-showcase-inner">

          <Link
            to="/"
            className="auth-brand"
          >
            <span className="auth-brand-mark">
              <Layers3 size={24} />
            </span>

            shopcart.
          </Link>

          <div className="auth-showcase-copy">

            <span className="auth-kicker">
              <Sparkles size={16} />
              UNA EXPERIENCIA DIFERENTE
            </span>

            <h1>
              Tu próxima compra
              <span> comienza aquí.</span>
            </h1>

            <p>
              Crea tu cuenta y descubre una manera
              más sencilla de explorar productos,
              gestionar compras y consultar tus pedidos.
            </p>

            <div className="auth-showcase-card">

              <ShieldCheck size={25} />

              <div>
                <strong>Una cuenta protegida</strong>

                <small>
                  Tus credenciales se validan
                  de manera segura desde nuestra API.
                </small>
              </div>

            </div>

          </div>

          <span className="auth-showcase-footer">
            SHOPCART / TECH CHALLENGE 360
          </span>

        </div>

      </section>

      {/* FORMULARIO */}

      <section className="auth-form-side">

        <div className="auth-form-shell">

          <Link
            to="/"
            className="auth-back"
          >
            ← Volver a la tienda
          </Link>

          {registeredEmail ? (

            /* REGISTRO COMPLETADO */

            <div
              className="register-success"
              role="status"
            >

              <span className="register-success-icon">
                <CheckCircle2 size={31} />
              </span>

              <span className="auth-form-eyebrow">
                REGISTRO COMPLETADO
              </span>

              <h2>¡Cuenta creada!</h2>

              <p>
                Registramos correctamente la cuenta:
              </p>

              <strong className="register-email">
                {registeredEmail}
              </strong>

              <p>
                Ahora puedes iniciar sesión
                con el correo y la contraseña
                que acabas de elegir.
              </p>

              <Link
                to="/login"
                className="auth-submit"
              >
                Iniciar sesión
                <ArrowRight size={18} />
              </Link>

            </div>

          ) : (

            /* NUEVA CUENTA */

            <>

              <span className="auth-form-eyebrow">
                ÚNETE A SHOPCART
              </span>

              <h2>Crear cuenta</h2>

              <p className="auth-intro">
                Completa tus datos para empezar.
              </p>

              <form
                className="auth-form"
                onSubmit={(event) => {
                  void handleSubmit(event);
                }}
              >

                <label htmlFor="register-email">
                  Correo electrónico
                </label>

                <div className="auth-input">

                  <Mail size={19} />

                  <input
                    id="register-email"
                    type="email"
                    name="email"
                    placeholder="correo@ejemplo.com"
                    autoComplete="email"
                    value={correo}
                    maxLength={254}
                    required
                    onChange={(event) => {
                      setCorreo(event.target.value);
                    }}
                  />

                </div>

                <label htmlFor="register-password">
                  Contraseña
                </label>

                <div className="auth-input">

                  <LockKeyhole size={19} />

                  <input
                    id="register-password"
                    type={
                      showPassword
                        ? "text"
                        : "password"
                    }
                    name="new-password"
                    placeholder="Mínimo 12 caracteres"
                    autoComplete="new-password"
                    minLength={12}
                    required
                    value={password}
                    onChange={(event) => {
                      setPassword(event.target.value);
                    }}
                  />

                  <button
                    className="auth-password-toggle"
                    type="button"
                    aria-label={
                      showPassword
                        ? "Ocultar contraseña"
                        : "Mostrar contraseña"
                    }
                    aria-pressed={showPassword}
                    onClick={() => {
                      setShowPassword((value) => !value);
                    }}
                  >
                    {showPassword ? (
                      <EyeOff size={19} />
                    ) : (
                      <Eye size={19} />
                    )}
                  </button>

                </div>

                <p className="register-password-hint">
                  Utiliza al menos 12 caracteres.
                </p>

                <label htmlFor="register-confirm">
                  Confirmar contraseña
                </label>

                <div className="auth-input">

                  <ShieldCheck size={19} />

                  <input
                    id="register-confirm"
                    type={
                      showPassword
                        ? "text"
                        : "password"
                    }
                    name="confirm-password"
                    placeholder="Repite tu contraseña"
                    autoComplete="new-password"
                    required
                    value={confirmPassword}
                    onChange={(event) => {
                      setConfirmPassword(event.target.value);
                    }}
                  />

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
                    ? "Creando cuenta..."
                    : "Crear mi cuenta"}

                  {!loading && (
                    <UserRoundPlus size={19} />
                  )}
                </button>

              </form>

              <p className="auth-form-note">
                ¿Ya tienes una cuenta?{" "}

                <Link to="/login">
                  Iniciar sesión
                </Link>
              </p>

            </>

          )}

        </div>

      </section>

    </main>
  );
}
