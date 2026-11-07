import {
  useEffect,
  useRef,
  useState,
  type FormEvent
} from "react";

import {
  ArrowLeft,
  FolderTree,
  Pencil,
  Plus,
  Power,
  RefreshCw,
  X
} from "lucide-react";

import { Link } from "react-router";

import {
  confirmAction,
  showError,
  showSuccess
} from "../../lib/alerts";

import {
  changeCategoryStatus,
  createAdminCategory,
  getAdminCategories,
  updateAdminCategory,
  type AdminCategory
} from "./admin.categories.api";

interface CategoryForm {
  nombre: string;
  descripcion: string;
}

const EMPTY_FORM: CategoryForm = {
  nombre: "",
  descripcion: ""
};

function errorMessage(error: unknown): string {
  return error instanceof Error
    ? error.message
    : "Ocurrió un error inesperado";
}

export function AdminCategoriesPage() {
  const [categories, setCategories] =
    useState<AdminCategory[]>([]);

  const [form, setForm] =
    useState<CategoryForm>(EMPTY_FORM);

  const [editingId, setEditingId] =
    useState<number | null>(null);

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const savingRef = useRef(false);

  const [error, setError] =
    useState<string | null>(null);

  const [reload, setReload] = useState(0);

  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("TODAS");

  // CONSULTAR CATEGORÍAS

  useEffect(() => {
    const controller = new AbortController();

    setLoading(true);
    setError(null);

    getAdminCategories(controller.signal)
      .then(data => {
        if (!controller.signal.aborted) {
          setCategories(data);
        }
      })
      .catch((cause: unknown) => {
        if (!controller.signal.aborted) {
          setError(errorMessage(cause));
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [reload]);

  function resetForm(): void {
    setEditingId(null);
    setForm(EMPTY_FORM);
  }

  function startEditing(category: AdminCategory): void {
    if (savingRef.current) return;

    setEditingId(category.idCategoria);

    setForm({
      nombre: category.nombre,
      descripcion: category.descripcion ?? ""
    });
  }


  // CREAR O ACTUALIZAR

  async function handleSave(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();

    if (savingRef.current) return;

    const nombre = form.nombre.trim();
    const descripcion = form.descripcion.trim();

    if (nombre.length < 3 || nombre.length > 120) {
      await showError(
        "Nombre inválido",
        "El nombre debe tener entre 3 y 120 caracteres."
      );
      return;
    }

    if (descripcion.length > 500) {
      await showError(
        "Descripción inválida",
        "La descripción no puede superar 500 caracteres."
      );
      return;
    }

    const isEditing = editingId !== null;

    savingRef.current = true;
    setSaving(true);

    try {
      const confirmed = await confirmAction({
        title: isEditing
          ? "¿Guardar cambios?"
          : "¿Crear categoría?",
        text: isEditing
          ? `Se actualizará la categoría ${nombre}.`
          : `Se creará la categoría ${nombre}.`,
        confirmText: isEditing
          ? "Guardar cambios"
          : "Crear categoría"
      });

      if (!confirmed) return;

      const input = {
        nombre,
        descripcion: descripcion || null
      };

      if (editingId !== null) {
        await updateAdminCategory(
          editingId,
          input
        );
      } else {
        await createAdminCategory(input);
      }

      resetForm();
      setReload(value => value + 1);

      await showSuccess(
        isEditing
          ? "Categoría actualizada"
          : "Categoría creada",
        "La operación se registró correctamente."
      );

    } catch (cause) {
      setReload(value => value + 1);

      await showError(
        "No se pudo confirmar la operación",
        errorMessage(cause) +
          ". Si hubo un problema de conexión, " +
          "revisa el listado antes de reintentar."
      );

    } finally {
      savingRef.current = false;
      setSaving(false);
    }
  }

  // ACTIVAR / DESACTIVAR

  async function handleStatus(
    category: AdminCategory
  ): Promise<void> {
    if (savingRef.current) return;

    const newStatus = !category.activa;

    savingRef.current = true;
    setSaving(true);

    try {
      const confirmed = await confirmAction({
        title: newStatus
          ? "¿Activar categoría?"
          : "¿Desactivar categoría?",
        text:
          `${category.nombre}: ` +
          (newStatus
            ? "volverá a estar disponible."
            : "dejará de estar disponible. " +
              "No se permitirá desactivarla " +
              "si tiene productos activos."),
        confirmText: newStatus
          ? "Sí, activar"
          : "Sí, desactivar",
        danger: !newStatus
      });

      if (!confirmed) return;

      await changeCategoryStatus(
        category.idCategoria,
        newStatus
      );

      setReload(value => value + 1);

      await showSuccess(
        "Estado actualizado",
        `La categoría ${category.nombre} ` +
        (newStatus
          ? "se activó correctamente."
          : "se desactivó correctamente.")
      );

    } catch (cause) {
      setReload(value => value + 1);

      await showError(
        "No se pudo actualizar",
        errorMessage(cause)
      );

    } finally {
      savingRef.current = false;
      setSaving(false);
    }
  }

      //BUSCADOR  
        const normalizedSearch = search
        .trim()
        .toLowerCase();

        const filteredCategories = categories.filter(
        category => {
            const matchesSearch =
            category.nombre
                .toLowerCase()
                .includes(normalizedSearch) ||
            (category.descripcion ?? "")
                .toLowerCase()
                .includes(normalizedSearch) ||
            String(category.idCategoria)
                .includes(normalizedSearch);

            const matchesStatus =
            statusFilter === "TODAS" ||
            (statusFilter === "ACTIVAS" &&
                category.activa) ||
            (statusFilter === "INACTIVAS" &&
                !category.activa);

            return matchesSearch && matchesStatus;
        }
        );
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

            <h1>Gestión de categorías</h1>

            <p>
              Organiza y administra las categorías
              del catálogo de ShopCart.
            </p>
          </div>

          <FolderTree size={38} />
        </header>

        <div className="admin-category-layout">

          {/* FORMULARIO */}

          <section className="admin-category-card">
            <div className="admin-category-heading">
              <h2>
                {editingId === null
                  ? "Nueva categoría"
                  : "Editar categoría"}
              </h2>

              {editingId !== null && (
                <button
                  type="button"
                  className="operator-refresh"
                  disabled={saving}
                  onClick={resetForm}
                >
                  <X size={15} />
                  Cancelar edición
                </button>
              )}
            </div>

            <form
              className="admin-category-form"
              onSubmit={event => {
                void handleSave(event);
              }}
            >
              <label htmlFor="category-name">
                Nombre
              </label>

              <input
                id="category-name"
                required
                minLength={3}
                maxLength={120}
                disabled={saving}
                placeholder="Ej. Electrónica"
                value={form.nombre}
                onChange={event => {
                  setForm(current => ({
                    ...current,
                    nombre: event.target.value
                  }));
                }}
              />

              <label htmlFor="category-description">
                Descripción
              </label>

              <textarea
                id="category-description"
                maxLength={500}
                rows={4}
                disabled={saving}
                placeholder="Descripción opcional"
                value={form.descripcion}
                onChange={event => {
                  setForm(current => ({
                    ...current,
                    descripcion: event.target.value
                  }));
                }}
              />

              <button
                className="operator-primary"
                type="submit"
                disabled={saving}
              >
                <Plus size={17} />

                {saving
                  ? "Procesando..."
                  : editingId !== null
                    ? "Guardar cambios"
                    : "Crear categoría"}
              </button>
            </form>
          </section>

          {/* LISTADO */}

          <section className="admin-category-card">
            <div className="admin-category-heading">
              <div>
                <h2>Categorías registradas</h2>
                <p>
                  {categories.length} registros
                </p>
              </div>

              <button
                type="button"
                className="operator-refresh"
                disabled={saving || loading}
                onClick={() => {
                  setReload(value => value + 1);
                }}
              >
                <RefreshCw size={16} />
                Actualizar
              </button>
            </div>
            
            <div className="admin-category-filters">
            <input
                type="search"
                placeholder="Buscar por nombre, descripción o ID..."
                aria-label="Buscar categorías"
                value={search}
                onChange={event => {
                setSearch(event.target.value);
                }}
            />

            <select
                aria-label="Filtrar por estado"
                value={statusFilter}
                onChange={event => {
                setStatusFilter(event.target.value);
                }}
            >
                <option value="TODAS">
                Todas las categorías
                </option>

                <option value="ACTIVAS">
                Activas
                </option>

                <option value="INACTIVAS">
                Inactivas
                </option>
            </select>
            </div>

            <p className="admin-category-count">
            Mostrando {filteredCategories.length}
            {" de "}
            {categories.length} categorías
            </p>

            {loading ? (
              <div
                className="admin-category-empty"
                role="status"
              >
                <span className="auth-spinner" />
                <p>Cargando categorías...</p>
              </div>

            ) : error ? (
              <div
                className="admin-category-empty"
                role="alert"
              >
                <p>{error}</p>

                <button
                  type="button"
                  className="operator-primary"
                  onClick={() => {
                    setReload(value => value + 1);
                  }}
                >
                  Reintentar
                </button>
              </div>

            ) : categories.length === 0 ? (
              <div className="admin-category-empty">
                <FolderTree size={35} />
                <p>No hay categorías registradas.</p>
              </div>
            ) : filteredCategories.length === 0 ? (
                <div className="admin-category-empty">
                    <p>
                    No se encontraron categorías
                    con los filtros seleccionados.
                    </p>
                </div>
            ) : (
              <div className="admin-category-list">
                {filteredCategories.map(category => (
                  <article
                    key={category.idCategoria}
                    className="admin-category-item"
                  >
                    <div className="admin-category-info">
                      <small>
                        ID #{category.idCategoria}
                      </small>

                      <h3>{category.nombre}</h3>

                      <p>
                        {category.descripcion ||
                          "Sin descripción"}
                      </p>

                      <span
                        className={
                          category.activa
                            ? "admin-status active"
                            : "admin-status inactive"
                        }
                      >
                        {category.activa
                          ? "Activa"
                          : "Inactiva"}
                      </span>
                    </div>

                    <div className="admin-category-buttons">
                      <button
                        type="button"
                        disabled={saving}
                        className="operator-refresh"
                        onClick={() => {
                          startEditing(category);
                        }}
                      >
                        <Pencil size={15} />
                        Editar
                      </button>

                      <button
                        type="button"
                        disabled={saving}
                        className="operator-refresh"
                        onClick={() => {
                          void handleStatus(category);
                        }}
                      >
                        <Power size={15} />
                        {category.activa
                          ? "Desactivar"
                          : "Activar"}
                      </button>
                    </div>
                  </article>
                ))}
              </div>
            )}
          </section>
        </div>
      </div>
    </main>
  );
}
