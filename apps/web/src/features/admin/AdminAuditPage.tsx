import {
  useEffect,
  useState,
  type FormEvent
} from "react";

import {
  ArrowLeft,
  ChevronLeft,
  ChevronRight,
  ClipboardList,
  Eye,
  RefreshCw,
  Search,
  X
} from "lucide-react";

import { Link } from "react-router";

import {
  getAdminAuditLogs,
  type AdminAuditEntry,
  type AdminAuditFilters,
  type AdminAuditResponse,
  type AuditModule
} from "./admin.audit.api";

// ==========================================
// CONFIGURACION
// ==========================================

const PAGE_SIZE = 20;

interface AuditFilterForm {
  modulo: AuditModule | "";
  idUsuario: string;
  fechaInicio: string;
  fechaFin: string;
}

const EMPTY_FILTERS: AuditFilterForm = {
  modulo: "",
  idUsuario: "",
  fechaInicio: "",
  fechaFin: ""
};

const AUDIT_MODULES: {
  value: AuditModule;
  label: string;
}[] = [
  {
    value: "CATALOGO",
    label: "Catálogo"
  },
  {
    value: "INVENTARIO",
    label: "Inventario"
  },
  {
    value: "CUPONES",
    label: "Cupones"
  },
  {
    value: "PEDIDOS",
    label: "Pedidos"
  },
  {
    value: "USUARIOS",
    label: "Usuarios"
  }
];

// ==========================================
// UTILIDADES
// ==========================================

function errorMessage(error: unknown): string {
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
    timeStyle: "short",
    timeZone: "UTC"
  }).format(date) + " UTC";
}

// ==========================================
// FORMATEAR JSON DE AUDITORIA
// ==========================================

function formatAuditJson(
  value: string | null
): string {
  if (value === null || value.trim() === "") {
    return "Sin valores registrados";
  }

  try {
    const parsed: unknown = JSON.parse(value);

    return JSON.stringify(
      parsed,
      null,
      2
    ) ?? value;

  } catch {
    // Si el contenido no se puede interpretar
    // como JSON, mostrarlo como texto.
    return value;
  }
}

// ==========================================
// VALIDAR FECHA
// ==========================================

function validDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }

  const date = new Date(
    `${value}T00:00:00.000Z`
  );

  return (
    !Number.isNaN(date.getTime()) &&
    date.toISOString().slice(0, 10) === value &&
    value < "9999-12-31"
  );
}

// ==========================================
// CONSTRUIR FILTROS PARA API
// ==========================================

function createFilters(
  form: AuditFilterForm
): AdminAuditFilters {
  const filters: AdminAuditFilters = {
    pagina: 1,
    tamanoPagina: PAGE_SIZE
  };

  if (form.modulo) {
    filters.modulo = form.modulo;
  }

  const idUsuario = form.idUsuario.trim();

  if (idUsuario) {
    if (!/^[1-9]\d*$/.test(idUsuario)) {
      throw new Error(
        "El ID del responsable debe ser un entero positivo."
      );
    }

    const parsedId = Number(idUsuario);

    if (
      !Number.isSafeInteger(parsedId) ||
      parsedId > 2147483647
    ) {
      throw new Error(
        "El ID del responsable está fuera de rango."
      );
    }

    filters.idUsuarioFiltro = parsedId;
  }

  if (form.fechaInicio) {
    if (!validDate(form.fechaInicio)) {
      throw new Error(
        "La fecha inicial no es válida."
      );
    }

    filters.fechaInicio = form.fechaInicio;
  }

  if (form.fechaFin) {
    if (!validDate(form.fechaFin)) {
      throw new Error(
        "La fecha final no es válida."
      );
    }

    filters.fechaFin = form.fechaFin;
  }

  if (
    form.fechaInicio &&
    form.fechaFin &&
    form.fechaInicio > form.fechaFin
  ) {
    throw new Error(
      "La fecha inicial no puede ser posterior a la final."
    );
  }

  return filters;
}

// ==========================================
// COMPONENTE PRINCIPAL
// ==========================================

export function AdminAuditPage() {

  // ========================================
  // 1. ESTADO DEL LISTADO
  // ========================================

  const [result, setResult] =
    useState<AdminAuditResponse | null>(null);

  const [loading, setLoading] =
    useState(true);

  const [error, setError] =
    useState<string | null>(null);

  const [revision, setRevision] =
    useState(0);

  // ========================================
  // 2. FILTROS
  // ========================================

  const [draft, setDraft] =
    useState<AuditFilterForm>({
      ...EMPTY_FILTERS
    });

  const [filters, setFilters] =
    useState<AdminAuditFilters>({
      pagina: 1,
      tamanoPagina: PAGE_SIZE
    });

  const [filterError, setFilterError] =
    useState<string | null>(null);

  // ========================================
  // 3. DETALLE SELECCIONADO
  // ========================================

  const [selectedEntry, setSelectedEntry] =
    useState<AdminAuditEntry | null>(null);

  // ========================================
  // 4. CONSULTAR AUDITORIA
  // ========================================

  useEffect(() => {
    const controller = new AbortController();

    setLoading(true);
    setError(null);

    getAdminAuditLogs(
      filters,
      controller.signal
    )
      .then(data => {
        if (controller.signal.aborted) {
          return;
        }

        const requestedPage =
          filters.pagina ?? 1;

        // Si la página ya no existe,
        // regresar a la última página válida.

        if (
          requestedPage > 1 &&
          requestedPage > data.pagination.totalPaginas
        ) {
          setSelectedEntry(null);

          setFilters(current => ({
            ...current,
            pagina: Math.max(
              1,
              data.pagination.totalPaginas
            )
          }));

          return;
        }

        setResult(data);
      })
      .catch((cause: unknown) => {
        if (controller.signal.aborted) {
          return;
        }

        setError(errorMessage(cause));
        setResult(null);
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => {
      controller.abort();
    };

  }, [filters, revision]);

  // ========================================
  // 5. APLICAR FILTROS
  // ========================================

  function handleApplyFilters(
    event: FormEvent<HTMLFormElement>
  ): void {
    event.preventDefault();

    try {
      const nextFilters = createFilters(draft);

      setFilterError(null);
      setSelectedEntry(null);
      setFilters(nextFilters);

    } catch (cause) {
      setFilterError(
        errorMessage(cause)
      );
    }
  }

  // ========================================
  // 6. LIMPIAR FILTROS
  // ========================================

  function handleClearFilters(): void {
    setDraft({
      ...EMPTY_FILTERS
    });

    setFilterError(null);
    setSelectedEntry(null);

    setFilters({
      pagina: 1,
      tamanoPagina: PAGE_SIZE
    });
  }

  // ========================================
  // 7. ACTUALIZAR LISTADO
  // ========================================

  function handleRefresh(): void {
    setSelectedEntry(null);

    setRevision(value => value + 1);
  }

  // ========================================
  // 8. CAMBIAR PAGINA
  // ========================================

  function changePage(nextPage: number): void {
    const totalPages =
      result?.pagination.totalPaginas ?? 0;

    if (
      !Number.isSafeInteger(nextPage) ||
      nextPage < 1 ||
      nextPage > totalPages ||
      loading
    ) {
      return;
    }

    setSelectedEntry(null);

    setFilters(current => ({
      ...current,
      pagina: nextPage
    }));
  }

  // ========================================
  // 9. MOSTRAR / OCULTAR DETALLE
  // ========================================

  function handleShowDetail(
    entry: AdminAuditEntry
  ): void {
    setSelectedEntry(current => {
      if (
        current?.idBitacora === entry.idBitacora
      ) {
        return null;
      }

      return entry;
    });
  }

  // ========================================
  // 10. DATOS PARA VISTA
  // ========================================

  const entries = result?.items ?? [];

  const pagination = result?.pagination;

  const currentPage =
    pagination?.pagina ??
    filters.pagina ??
    1;

  const totalPages =
    pagination?.totalPaginas ?? 0;

  const totalRecords =
    pagination?.totalRegistros ?? 0;

  const displayPages = Math.max(
    1,
    totalPages
  );

  const canGoBack = currentPage > 1;

  const canGoForward =
    currentPage < totalPages;

  // ========================================
  // 11. INTERFAZ
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

            <h1>Bitácora de auditoría</h1>

            <p>
              Consulta quién realizó cambios
              en el sistema y cuándo ocurrieron.
            </p>
          </div>

          <ClipboardList size={38} />
        </header>

        {/* ==================================
            FILTROS
        ================================== */}

        <section className="admin-audit-card">
          <div className="admin-audit-heading">
            <div>
              <h2>Filtros de auditoría</h2>

              <p>
                Busca eventos por módulo,
                responsable y fecha.
              </p>
            </div>

            <Search size={22} />
          </div>

          <form
            className="admin-audit-filters"
            onSubmit={handleApplyFilters}
          >

            {/* MODULO */}

            <label htmlFor="audit-module">
              Módulo

              <select
                id="audit-module"
                value={draft.modulo}
                onChange={event => {
                  setDraft(current => ({
                    ...current,
                    modulo:
                      event.target.value as
                        AuditModule | ""
                  }));
                }}
              >
                <option value="">
                  Todos los módulos
                </option>

                {AUDIT_MODULES.map(module => (
                  <option
                    key={module.value}
                    value={module.value}
                  >
                    {module.label}
                  </option>
                ))}
              </select>
            </label>

            {/* USUARIO RESPONSABLE */}

            <label htmlFor="audit-user">
              ID del responsable

              <input
                id="audit-user"
                type="text"
                inputMode="numeric"
                placeholder="Ej. 1"
                value={draft.idUsuario}
                onChange={event => {
                  setDraft(current => ({
                    ...current,
                    idUsuario: event.target.value
                  }));
                }}
              />
            </label>

            {/* FECHA INICIAL */}

            <label htmlFor="audit-start-date">
              Fecha inicial

              <input
                id="audit-start-date"
                type="date"
                value={draft.fechaInicio}
                onChange={event => {
                  setDraft(current => ({
                    ...current,
                    fechaInicio: event.target.value
                  }));
                }}
              />
            </label>

            {/* FECHA FINAL */}

            <label htmlFor="audit-end-date">
              Fecha final

              <input
                id="audit-end-date"
                type="date"
                value={draft.fechaFin}
                onChange={event => {
                  setDraft(current => ({
                    ...current,
                    fechaFin: event.target.value
                  }));
                }}
              />
            </label>

            <div className="admin-audit-form-actions">
              <button
                type="submit"
                className="operator-primary"
                disabled={loading}
              >
                <Search size={17} />
                Aplicar filtros
              </button>

              <button
                type="button"
                className="operator-refresh"
                disabled={loading}
                onClick={handleClearFilters}
              >
                Limpiar
              </button>
            </div>
          </form>

          {filterError && (
            <p
              role="alert"
              className="auth-error"
            >
              {filterError}
            </p>
          )}

          <p className="admin-audit-muted">
            Las fechas de auditoría se consultan
            y presentan en UTC.
          </p>
        </section>

        {/* ==================================
            LISTADO DE AUDITORIA
        ================================== */}

        <section className="admin-audit-card">
          <div className="admin-audit-heading">
            <div>
              <h2>Historial de eventos</h2>

              <p>
                {loading
                  ? "Consultando registros..."
                  : `${totalRecords} eventos encontrados`}
              </p>
            </div>

            <button
              type="button"
              className="operator-refresh"
              onClick={handleRefresh}
              disabled={loading}
            >
              <RefreshCw size={16} />
              Actualizar
            </button>
          </div>

          {/* CARGANDO */}

          {loading ? (
            <div
              className="admin-audit-empty"
              role="status"
            >
              <span className="auth-spinner" />

              <p>
                Cargando registros de auditoría...
              </p>
            </div>

          ) : error ? (

            /* ERROR */

            <div
              className="admin-audit-empty"
              role="alert"
            >
              <p>{error}</p>

              <button
                type="button"
                className="operator-primary"
                onClick={handleRefresh}
              >
                Reintentar
              </button>
            </div>

          ) : entries.length === 0 ? (

            /* SIN REGISTROS */

            <div className="admin-audit-empty">
              <ClipboardList size={34} />

              <p>
                No se encontraron eventos
                con los filtros seleccionados.
              </p>
            </div>

          ) : (

            /* TABLA */

            <div
              className="admin-audit-table-wrap"
              style={{ overflowX: "auto" }}
            >
              <table className="admin-audit-table">
                <caption className="admin-audit-sr-only">
                  Registros de auditoría de ShopCart
                </caption>

                <thead>
                  <tr>
                    <th scope="col">Fecha</th>
                    <th scope="col">Evento</th>
                    <th scope="col">Módulo</th>
                    <th scope="col">Acción</th>
                    <th scope="col">Responsable</th>
                    <th scope="col">Entidad</th>
                    <th scope="col">Detalle</th>
                  </tr>
                </thead>

                <tbody>
                  {entries.map(entry => {
                    const isSelected =
                      selectedEntry?.idBitacora ===
                      entry.idBitacora;

                    return (
                      <tr key={entry.idBitacora}>
                        <td>
                          <span className="admin-audit-date">
                            {formatDate(
                              entry.fechaRegistro
                            )}
                          </span>
                        </td>

                        <td>
                          <span className="admin-audit-id">
                            #{entry.idBitacora}
                          </span>
                        </td>

                        <td>
                          <span className="admin-audit-module">
                            {entry.modulo}
                          </span>
                        </td>

                        <td>
                          <span className="admin-audit-action">
                            {entry.accion}
                          </span>
                        </td>

                        <td>
                          Usuario #{entry.idUsuario}
                        </td>

                        <td>
                          <div className="admin-audit-entity">
                            <strong>
                              {entry.entidad}
                            </strong>

                            <small>
                              ID: {entry.idEntidad}
                            </small>
                          </div>
                        </td>

                        <td>
                          <button
                            type="button"
                            className="operator-refresh"
                            aria-expanded={isSelected}
                            aria-controls="admin-audit-details"
                            onClick={() => {
                              handleShowDetail(entry);
                            }}
                          >
                            <Eye size={16} />

                            {isSelected
                              ? "Ocultar"
                              : "Ver detalle"}
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}

          {/* ==================================
              PAGINACION
          ================================== */}

          <div className="admin-audit-pagination">
            <p>
              Página {currentPage} de {displayPages}
              {" · "}
              {totalRecords} eventos
            </p>

            <div>
              <button
                type="button"
                className="operator-refresh"
                disabled={
                  loading || !canGoBack
                }
                onClick={() => {
                  changePage(currentPage - 1);
                }}
              >
                <ChevronLeft size={16} />
                Anterior
              </button>

              <button
                type="button"
                className="operator-refresh"
                disabled={
                  loading || !canGoForward
                }
                onClick={() => {
                  changePage(currentPage + 1);
                }}
              >
                Siguiente
                <ChevronRight size={16} />
              </button>
            </div>
          </div>
        </section>

        {/* ==================================
            DETALLE DEL EVENTO
        ================================== */}

        {!loading && !error && selectedEntry && (
          <section
            id="admin-audit-details"
            className="admin-audit-card admin-audit-detail"
            role="region"
            aria-labelledby="audit-detail-title"
          >
            <div className="admin-audit-heading">
              <div>
                <h2 id="audit-detail-title">
                  Detalle del evento
                  {" #"}
                  {selectedEntry.idBitacora}
                </h2>

                <p>
                  Información registrada
                  en la bitácora del sistema.
                </p>
              </div>

              <button
                type="button"
                className="operator-refresh"
                onClick={() => {
                  setSelectedEntry(null);
                }}
              >
                <X size={16} />
                Cerrar
              </button>
            </div>

            {/* INFORMACION GENERAL */}

            <div className="admin-audit-detail-grid">

              <div>
                <small>Módulo</small>
                <strong>
                  {selectedEntry.modulo}
                </strong>
              </div>

              <div>
                <small>Acción</small>
                <strong>
                  {selectedEntry.accion}
                </strong>
              </div>

              <div>
                <small>Responsable</small>
                <strong>
                  Usuario #{selectedEntry.idUsuario}
                </strong>
              </div>

              <div>
                <small>Entidad afectada</small>
                <strong>
                  {selectedEntry.entidad}
                  {" #"}
                  {selectedEntry.idEntidad}
                </strong>
              </div>

              <div>
                <small>Fecha del evento</small>
                <strong>
                  {formatDate(
                    selectedEntry.fechaRegistro
                  )}
                </strong>
              </div>

            </div>

            {/* COMPARACION DE VALORES */}

            <div className="admin-audit-json-grid">

              <div className="admin-audit-json-card">
                <h3>
                  Valores anteriores
                </h3>

                <pre>
                  <code>
                    {formatAuditJson(
                      selectedEntry.valoresAnteriores
                    )}
                  </code>
                </pre>
              </div>

              <div className="admin-audit-json-card">
                <h3>
                  Valores nuevos
                </h3>

                <pre>
                  <code>
                    {formatAuditJson(
                      selectedEntry.valoresNuevos
                    )}
                  </code>
                </pre>
              </div>

            </div>

            <p className="admin-audit-muted">
              Vista de solo lectura.
              No se permite modificar
              ni eliminar eventos.
            </p>
          </section>
        )}

      </div>
    </main>
  );
}
