import {
  useEffect,
  useRef,
  useState,
  type FormEvent
} from "react";

import {
  ArrowLeft,
  ChevronLeft,
  ChevronRight,
  Plus,
  RefreshCw,
  Search,
  ShieldCheck,
  UserRound,
  UsersRound
} from "lucide-react";

import { Link } from "react-router";

import {
  useAuth
} from "../../auth/AuthProvider";

import type {
  Role
} from "../../lib/auth";

import {
  confirmAction,
  showError,
  showSuccess
} from "../../lib/alerts";

import {
  getAdminUsers,
  createAdminUser,
  changeAdminUserRole,
  changeAdminUserStatus,
  type AdminUser,
  type AdminUsersResponse,
  type CreateAdminUserInput
} from "./admin.users.api";

// ==========================================
// CONSTANTES Y TIPOS
// ==========================================

const PAGE_SIZE = 10;

type RoleFilter = Role | "";
type StatusFilter = "" | "1" | "0";

const EMPTY_FORM: CreateAdminUserInput = {
  correo: "",
  password: "",
  rol: "Cliente"
};

function messageFrom(error: unknown): string {
  return error instanceof Error
    ? error.message
    : "Ocurrió un error inesperado";
}

function formatDate(value: string): string {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "Fecha no disponible";
  }

  return new Intl.DateTimeFormat("es-GT", {
    dateStyle: "medium",
    timeStyle: "short"
  }).format(date);
}

// ==========================================
// PAGINA DE ADMINISTRACION
// ==========================================

export function AdminUsersPage() {
  const { session } = useAuth();

  const currentUserId =
    session?.user.id ?? null;

  // ========================================
  // ESTADO DEL LISTADO
  // ========================================

  const [result, setResult] =
    useState<AdminUsersResponse | null>(null);

  const [loading, setLoading] =
    useState(true);

  const [error, setError] =
    useState<string | null>(null);

  const [revision, setRevision] =
    useState(0);

  // ========================================
  // FILTROS Y PAGINACION
  // ========================================

  const [page, setPage] = useState(1);

  const [searchInput, setSearchInput] =
    useState("");

  const [appliedSearch, setAppliedSearch] =
    useState("");

  const [roleFilter, setRoleFilter] =
    useState<RoleFilter>("");

  const [statusFilter, setStatusFilter] =
    useState<StatusFilter>("");

  // ========================================
  // FORMULARIO DE CREACION
  // ========================================

  const [form, setForm] =
    useState<CreateAdminUserInput>(EMPTY_FORM);

  const [showCreateForm, setShowCreateForm] =
    useState(false);

  const [saving, setSaving] =
    useState(false);

  // Evita solicitudes administrativas
  // simultaneas por doble clic.

  const actionLock = useRef(false);

  // Rol seleccionado para cada usuario,
  // antes de confirmar el cambio.

  const [roleDrafts, setRoleDrafts] =
    useState<Partial<Record<number, Role>>>({});

  // ========================================
  // 1. CONSULTAR USUARIOS
  // ========================================

  useEffect(() => {
    const controller = new AbortController();

    setLoading(true);
    setError(null);

    getAdminUsers(
      {
        pagina: page,
        tamanoPagina: PAGE_SIZE,
        busqueda: appliedSearch,
        rol: roleFilter || null,
        activo:
          statusFilter === ""
            ? null
            : statusFilter === "1"
      },
      controller.signal
    )
      .then(data => {
        if (controller.signal.aborted) return;

        // Si la pagina actual queda vacia
        // y existen paginas anteriores,
        // regresar a una pagina valida.

        if (
          page > 1 &&
          data.pagination.totalPaginas < page
        ) {
          setPage(
            Math.max(1, data.pagination.totalPaginas)
          );
          return;
        }

        setResult(data);
      })
      .catch((cause: unknown) => {
        if (controller.signal.aborted) return;

        setError(messageFrom(cause));
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => {
      controller.abort();
    };

  }, [
    page,
    appliedSearch,
    roleFilter,
    statusFilter,
    revision
  ]);

  // ========================================
  // 2. BUSCAR USUARIOS
  // ========================================

  function handleSearch(
    event: FormEvent<HTMLFormElement>
  ): void {
    event.preventDefault();

    setPage(1);
    setAppliedSearch(searchInput.trim());
  }

  function clearFilters(): void {
    setSearchInput("");
    setAppliedSearch("");
    setRoleFilter("");
    setStatusFilter("");
    setPage(1);
  }

  function refreshUsers(): void {
    setRevision(value => value + 1);
  }

  // ========================================
  // 3. ACTUALIZAR FORMULARIO
  // ========================================

  function changeForm(
    field: keyof CreateAdminUserInput,
    value: string
  ): void {
    setForm(current => ({
      ...current,
      [field]: value
    }));
  }

  // ========================================
  // 4. CREAR USUARIO
  // ========================================

  async function handleCreate(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();

    if (actionLock.current) return;

    const correo = form.correo
      .trim()
      .toLowerCase();

    const password = form.password;

    if (
      password.length < 12 ||
      new TextEncoder()
        .encode(password)
        .length > 72
    ) {
      await showError(
        "Contraseña inválida",
        "Debe tener al menos 12 caracteres " +
        "y no superar 72 bytes."
      );
      return;
    }

    actionLock.current = true;
    setSaving(true);

    try {
      const confirmed = await confirmAction({
        title: "¿Crear usuario?",
        text:
          `Se registrará ${correo} ` +
          `con rol ${form.rol}.`,
        confirmText: "Crear usuario"
      });

      if (!confirmed) return;

      await createAdminUser({
        correo,
        password,
        rol: form.rol
      });

      // Limpiar la contraseña después
      // de completar la operación.

      setForm(EMPTY_FORM);
      setShowCreateForm(false);

      clearFilters();
      refreshUsers();

      await showSuccess(
        "Usuario creado",
        "La cuenta se registró correctamente."
      );

    } catch (cause) {
      // Refrescar por si el servidor confirmó
      // la operación pero falló la respuesta.

      setForm(current => ({
        ...current,
        password: ""
      }));

      refreshUsers();

      await showError(
        "No se pudo confirmar la creación",
        messageFrom(cause) +
          ". Revisa el listado antes de reintentar."
      );

    } finally {
      actionLock.current = false;
      setSaving(false);
    }
  }

  // ========================================
  // 5. CAMBIAR ROL
  // ========================================

  async function handleChangeRole(
    user: AdminUser
  ): Promise<void> {
    if (
      actionLock.current ||
      user.idUsuario === currentUserId
    ) {
      return;
    }

    const newRole =
      roleDrafts[user.idUsuario] ?? user.rol;

    if (newRole === user.rol) return;

    actionLock.current = true;
    setSaving(true);

    try {
      const confirmed = await confirmAction({
        title: "¿Cambiar rol?",
        text:
          `${user.correo} pasará de ` +
          `${user.rol} a ${newRole}. ` +
          "Sus sesiones actuales serán invalidadas.",
        confirmText: "Cambiar rol",
        danger: true
      });

      if (!confirmed) return;

      await changeAdminUserRole(
        user.idUsuario,
        newRole
      );

      setRoleDrafts(current => {
        const next = { ...current };
        delete next[user.idUsuario];
        return next;
      });

      refreshUsers();

      await showSuccess(
        "Rol actualizado",
        `El usuario ahora tiene rol ${newRole}.`
      );

    } catch (cause) {
      refreshUsers();

      await showError(
        "No se pudo actualizar el rol",
        messageFrom(cause)
      );

    } finally {
      actionLock.current = false;
      setSaving(false);
    }
  }

  // ========================================
  // 6. ACTIVAR / DESACTIVAR
  // ========================================

  async function handleChangeStatus(
    user: AdminUser
  ): Promise<void> {
    if (
      actionLock.current ||
      user.idUsuario === currentUserId
    ) {
      return;
    }

    const newStatus = !user.activo;

    actionLock.current = true;
    setSaving(true);

    try {
      const confirmed = await confirmAction({
        title: newStatus
          ? "¿Activar usuario?"
          : "¿Desactivar usuario?",
        text:
          `${user.correo} ` +
          (newStatus
            ? "podrá volver a iniciar sesión."
            : "perderá acceso al sistema."),
        confirmText: newStatus
          ? "Activar"
          : "Desactivar",
        danger: !newStatus
      });

      if (!confirmed) return;

      await changeAdminUserStatus(
        user.idUsuario,
        newStatus
      );

      refreshUsers();

      await showSuccess(
        "Estado actualizado",
        newStatus
          ? "El usuario fue activado."
          : "El usuario fue desactivado."
      );

    } catch (cause) {
      refreshUsers();

      await showError(
        "No se pudo actualizar el estado",
        messageFrom(cause)
      );

    } finally {
      actionLock.current = false;
      setSaving(false);
    }
  }

  // ========================================
  // 7. DATOS PARA LA VISTA
  // ========================================

  const users = result?.items ?? [];

  const pagination = result?.pagination;

  const totalPages = Math.max(
    1,
    pagination?.totalPaginas ?? 1
  );

  const totalUsers =
    pagination?.totalRegistros ?? 0;

  const canGoBack = page > 1;

  const canGoForward =
    page < totalPages;

  // ========================================
  // 8. INTERFAZ
  // ========================================

  return (
    <main className="operator-page">
      <div className="operator-container">

        <Link
          to="/administracion"
          className="orders-back"
        >
          <ArrowLeft size={18} />
          Volver al administrador
        </Link>

        <header className="operator-heading">
          <div>
            <span className="eyebrow">
              SHOPCART / ADMINISTRACIÓN
            </span>

            <h1>Gestión de usuarios</h1>

            <p>
              Administra cuentas, permisos
              y accesos al sistema.
            </p>
          </div>

          <UsersRound size={38} />
        </header>

        <div className="admin-users-toolbar">
          <div>
            <h2>Usuarios registrados</h2>

            <p>
              {totalUsers} usuarios encontrados
            </p>
          </div>

          <button
            type="button"
            className="operator-primary"
            disabled={saving}
            onClick={() => {
              setShowCreateForm(value => !value);
            }}
          >
            <Plus size={18} />
            {showCreateForm
              ? "Cerrar formulario"
              : "Nuevo usuario"}
          </button>
        </div>

        {/* ==================================
            FORMULARIO DE CREACION
        ================================== */}

        {showCreateForm && (
          <section className="admin-users-card">
            <h2>Crear usuario</h2>

            <form
              className="admin-users-form"
              onSubmit={event => {
                void handleCreate(event);
              }}
            >
              <label htmlFor="admin-user-email">
                Correo electrónico
              </label>

              <input
                id="admin-user-email"
                type="email"
                required
                maxLength={254}
                autoComplete="off"
                disabled={saving}
                placeholder="usuario@ejemplo.com"
                value={form.correo}
                onChange={event => {
                  changeForm(
                    "correo",
                    event.target.value
                  );
                }}
              />

              <label htmlFor="admin-user-password">
                Contraseña inicial
              </label>

              <input
                id="admin-user-password"
                type="password"
                required
                minLength={12}
                autoComplete="new-password"
                disabled={saving}
                placeholder="Mínimo 12 caracteres"
                value={form.password}
                onChange={event => {
                  changeForm(
                    "password",
                    event.target.value
                  );
                }}
              />

              <p className="admin-users-help">
                La contraseña se procesa con bcrypt
                en el backend. No se mostrará en
                los listados.
              </p>

              <label htmlFor="admin-user-role">
                Rol
              </label>

              <select
                id="admin-user-role"
                disabled={saving}
                value={form.rol}
                onChange={event => {
                  changeForm(
                    "rol",
                    event.target.value
                  );
                }}
              >
                <option value="Cliente">
                  Cliente
                </option>

                <option value="Operador">
                  Operador
                </option>

                <option value="Administrador">
                  Administrador
                </option>
              </select>

              <button
                type="submit"
                className="operator-primary"
                disabled={saving}
              >
                <Plus size={18} />
                {saving
                  ? "Procesando..."
                  : "Crear usuario"}
              </button>
            </form>
          </section>
        )}

        {/* ==================================
            BUSCADOR Y FILTROS
        ================================== */}

        <section className="admin-users-card">
          <div className="admin-users-section-heading">
            <h2>Consultar usuarios</h2>

            <button
              type="button"
              className="operator-refresh"
              disabled={loading || saving}
              onClick={refreshUsers}
            >
              <RefreshCw size={16} />
              Actualizar
            </button>
          </div>

          <form
            className="admin-users-search"
            onSubmit={handleSearch}
          >
            <label
              className="admin-users-sr-only"
              htmlFor="admin-users-search"
            >
              Buscar por correo
            </label>

            <input
              id="admin-users-search"
              type="search"
              maxLength={254}
              placeholder="Buscar por correo..."
              value={searchInput}
              disabled={saving}
              onChange={event => {
                setSearchInput(event.target.value);
              }}
            />

            <button
              type="submit"
              className="operator-primary"
              disabled={saving}
            >
              <Search size={17} />
              Buscar
            </button>
          </form>

          <div className="admin-users-filters">

            <label>
              Rol

              <select
                value={roleFilter}
                disabled={saving}
                onChange={event => {
                  setRoleFilter(
                    event.target.value as RoleFilter
                  );
                  setPage(1);
                }}
              >
                <option value="">
                  Todos los roles
                </option>
                <option value="Cliente">
                  Cliente
                </option>
                <option value="Operador">
                  Operador
                </option>
                <option value="Administrador">
                  Administrador
                </option>
              </select>
            </label>

            <label>
              Estado

              <select
                value={statusFilter}
                disabled={saving}
                onChange={event => {
                  setStatusFilter(
                    event.target.value as StatusFilter
                  );
                  setPage(1);
                }}
              >
                <option value="">
                  Todos los estados
                </option>
                <option value="1">
                  Activos
                </option>
                <option value="0">
                  Inactivos
                </option>
              </select>
            </label>

            <button
              type="button"
              className="operator-refresh"
              disabled={saving}
              onClick={clearFilters}
            >
              Limpiar filtros
            </button>
          </div>
        </section>

        {/* ==================================
            LISTADO DE USUARIOS
        ================================== */}

        <section className="admin-users-card">
          <div className="admin-users-section-heading">
            <h2>Listado de usuarios</h2>

            <span className="admin-users-count">
              {totalUsers} registros
            </span>
          </div>

          {loading ? (
            <div
              className="admin-users-empty"
              role="status"
            >
              <span className="auth-spinner" />
              <p>Cargando usuarios...</p>
            </div>

          ) : error ? (
            <div
              className="admin-users-empty"
              role="alert"
            >
              <p>{error}</p>

              <button
                type="button"
                className="operator-primary"
                onClick={refreshUsers}
              >
                Reintentar
              </button>
            </div>

          ) : users.length === 0 ? (
            <div className="admin-users-empty">
              <UsersRound size={34} />

              <p>
                No se encontraron usuarios
                con los filtros seleccionados.
              </p>
            </div>

          ) : (
            <div className="admin-users-list">
              {users.map(user => {
                const isCurrentUser =
                  user.idUsuario === currentUserId;

                const draftRole =
                  roleDrafts[user.idUsuario] ??
                  user.rol;

                const hasRoleChange =
                  draftRole !== user.rol;

                return (
                  <article
                    key={user.idUsuario}
                    className="admin-users-item"
                  >
                    <div className="admin-users-avatar">
                      <UserRound size={22} />
                    </div>

                    <div className="admin-users-info">
                      <div className="admin-users-identity">
                        <h3>{user.correo}</h3>

                        <span
                          className={
                            user.activo
                              ? "admin-status active"
                              : "admin-status inactive"
                          }
                        >
                          {user.activo
                            ? "Activo"
                            : "Inactivo"}
                        </span>
                      </div>

                      <p>
                        ID #{user.idUsuario}
                        {" · "}
                        Registrado el{" "}
                        {formatDate(user.fechaCreacion)}
                      </p>

                      {isCurrentUser && (
                        <span className="admin-users-own">
                          <ShieldCheck size={14} />
                          Tu cuenta
                        </span>
                      )}
                    </div>

                    <div className="admin-users-actions">
                      <label>
                        Rol

                        <select
                          value={draftRole}
                          disabled={
                            saving ||
                            isCurrentUser
                          }
                          onChange={event => {
                            const newRole =
                              event.target.value as Role;

                            setRoleDrafts(current => ({
                              ...current,
                              [user.idUsuario]: newRole
                            }));
                          }}
                        >
                          <option value="Cliente">
                            Cliente
                          </option>
                          <option value="Operador">
                            Operador
                          </option>
                          <option value="Administrador">
                            Administrador
                          </option>
                        </select>
                      </label>

                      <button
                        type="button"
                        className="operator-refresh"
                        disabled={
                          saving ||
                          isCurrentUser ||
                          !hasRoleChange
                        }
                        onClick={() => {
                          void handleChangeRole(user);
                        }}
                      >
                        Cambiar rol
                      </button>

                      <button
                        type="button"
                        className={
                          user.activo
                            ? "admin-users-status-button danger"
                            : "admin-users-status-button"
                        }
                        disabled={
                          saving ||
                          isCurrentUser
                        }
                        onClick={() => {
                          void handleChangeStatus(user);
                        }}
                      >
                        {user.activo
                          ? "Desactivar"
                          : "Activar"}
                      </button>
                    </div>
                  </article>
                );
              })}
            </div>
          )}

          {/* ==================================
              PAGINACION
          ================================== */}

          <div className="admin-users-pagination">
            <p>
              Página {page} de {totalPages}
            </p>

            <div>
              <button
                type="button"
                className="operator-refresh"
                disabled={
                  loading ||
                  saving ||
                  !canGoBack
                }
                onClick={() => {
                  setPage(value => value - 1);
                }}
              >
                <ChevronLeft size={16} />
                Anterior
              </button>

              <button
                type="button"
                className="operator-refresh"
                disabled={
                  loading ||
                  saving ||
                  !canGoForward
                }
                onClick={() => {
                  setPage(value => value + 1);
                }}
              >
                Siguiente
                <ChevronRight size={16} />
              </button>
            </div>
          </div>
        </section>

      </div>
    </main>
  );
}
