import {
  useEffect,
  useRef,
  useState,
  type FormEvent
} from "react";

import Swal from "sweetalert2";

import {
  ArrowLeft,
  ArrowRight,
  ClipboardList,
  RefreshCw,
  Truck
} from "lucide-react";

import { Link } from "react-router";

import { formatGTQ } from "../../lib/catalog";

import {
  formatOrderDate,
  orderStatusLabel,
  type OrderStatus
} from "../orders/orders.api";

import {
  advanceOrderStatus,
  listOperatorOrders,
  nextOrderStatus,
  type OperatorOrder,
  type OperatorOrdersFilters,
  type OperatorOrdersResult
} from "./operations.api";

const STATUSES: OrderStatus[] = [
  "PAGADO",
  "PREPARANDO",
  "DESPACHADO",
  "ENTREGADO",
  "CANCELADO",
  "DEVUELTO_PARCIAL",
  "DEVUELTO_TOTAL"
];

interface FilterForm {
  estado: OrderStatus | "";
  idCliente: string;
  fechaInicio: string;
  fechaFin: string;
}

const INITIAL_FILTERS: FilterForm = {
  estado: "",
  idCliente: "",
  fechaInicio: "",
  fechaFin: ""
};

function errorMessage(error: unknown): string {
  return error instanceof Error
    ? error.message
    : "No se pudo completar la operación";
}

export function OperatorOrdersPage() {
  const [form, setForm] =
    useState<FilterForm>(INITIAL_FILTERS);

  const [filters, setFilters] =
    useState<OperatorOrdersFilters>({
      pagina: 1
    });

  const [result, setResult] =
    useState<OperatorOrdersResult | null>(null);

  const [loading, setLoading] = useState(true);
  const [savingId, setSavingId] =
    useState<string | null>(null);

  const savingRef = useRef(false);

  const [observations, setObservations] =
    useState<Record<string, string>>({});

  const [listError, setListError] =
    useState<string | null>(null);

  const [actionError, setActionError] =
    useState<string | null>(null);

  const [notice, setNotice] =
    useState<string | null>(null);

  const [reload, setReload] = useState(0);

  // ========================================
  // CONSULTAR PEDIDOS
  // ========================================

  useEffect(() => {
    const controller = new AbortController();

    setLoading(true);
    setListError(null);

    listOperatorOrders(
      filters,
      controller.signal
    )
      .then(data => {
        if (!controller.signal.aborted) {
          setResult(data);
        }
      })
      .catch((error: unknown) => {
        if (!controller.signal.aborted) {
          setListError(errorMessage(error));
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [filters, reload]);

  // ========================================
  // APLICAR FILTROS
  // ========================================

  function applyFilters(
    event: FormEvent<HTMLFormElement>
  ): void {
    event.preventDefault();

    setActionError(null);
    setNotice(null);

    let idCliente: number | undefined;

    if (form.idCliente.trim()) {
      idCliente = Number(form.idCliente);

      if (
        !Number.isSafeInteger(idCliente) ||
        idCliente <= 0 ||
        idCliente > 2147483647
      ) {
        setActionError(
          "El ID del cliente debe ser un entero positivo válido."
        );
        return;
      }
    }

    if (
      form.fechaInicio &&
      form.fechaFin &&
      form.fechaInicio > form.fechaFin
    ) {
      setActionError(
        "La fecha inicial no puede superar la final."
      );
      return;
    }

    setFilters({
      pagina: 1,
      ...(form.estado
        ? { estado: form.estado }
        : {}),
      ...(idCliente
        ? { idCliente }
        : {}),
      ...(form.fechaInicio
        ? { fechaInicio: form.fechaInicio }
        : {}),
      ...(form.fechaFin
        ? { fechaFin: form.fechaFin }
        : {})
    });
  }

  // ========================================
  // AVANZAR UN PEDIDO
  // ========================================

  async function handleAdvance(
    order: OperatorOrder
  ): Promise<void> {

    const next = nextOrderStatus(order.estado);

    if (!next || savingRef.current) return;

    
    const confirmation = await Swal.fire({
    title: "¿Actualizar pedido?",
    text:
        `¿Cambiar el pedido #${order.idPedido} ` +
        `de ${orderStatusLabel(order.estado)} ` +
        `a ${orderStatusLabel(next)}?`,
    icon: "question",
    showCancelButton: true,
    confirmButtonText: "Sí, actualizar",
    cancelButtonText: "Cancelar",
    confirmButtonColor: "#7162ed",
    cancelButtonColor: "#85899b",
    reverseButtons: true
    });

    if (!confirmation.isConfirmed) {
    return;
    }


    savingRef.current = true;
    setSavingId(order.idPedido);
    setActionError(null);
    setNotice(null);

    try {
      const result = await advanceOrderStatus(
        order.idPedido,
        next,
        observations[order.idPedido]
      );

      setNotice(
        `Pedido #${result.idPedido}: ` +
        `estado actualizado a ` +
        `${orderStatusLabel(result.estadoNuevo)}.`
      );

      setObservations(current => ({
        ...current,
        [order.idPedido]: ""
      }));

    } catch (error) {
      setActionError(errorMessage(error));
    } finally {
      savingRef.current = false;
      setSavingId(null);

      // Recuperar siempre los estados reales
      // después de un intento de actualización.
      setReload(current => current + 1);
    }
  }

  const orders = result?.items ?? [];
  const pagination = result?.pagination;

  return (
    <main className="operator-page">
      <div className="operator-container">

        <Link
          className="orders-back"
          to="/operacion"
        >
          <ArrowLeft size={17} />
          Volver al panel
        </Link>

        <header className="operator-heading">
          <div>
            <span className="eyebrow">
              SHOPCART / OPERACIONES
            </span>

            <h1>Gestión de pedidos</h1>

            <p>
              Consulta compras y controla su
              preparación, despacho y entrega.
            </p>
          </div>

          <ClipboardList size={38} />
        </header>

        {/* FILTROS */}

        <form
          className="operator-filters"
          onSubmit={applyFilters}
        >
           
            <label>
            Estado
            <select
                value={form.estado}
                onChange={(event) => {
                const value = event.currentTarget.value;

                const selectedStatus =
                    STATUSES.find(
                    (status) => status === value
                    ) ?? "";

                setForm((current) => ({
                    ...current,
                    estado: selectedStatus,
                }));
                }}
            >
                <option value="">Todos</option>

                {STATUSES.map((status) => (
                <option
                    key={status}
                    value={status}
                >
                    {orderStatusLabel(status)}
                </option>
                ))}
            </select>
            </label>

          <label>
            ID del cliente
            <input
              type="number"
              min={1}
              max={2147483647}
              step={1}
              placeholder="Todos"
              value={form.idCliente}
              onChange={event => {
                setForm(current => ({
                  ...current,
                  idCliente: event.target.value
                }));
              }}
            />
          </label>

          <label>
            Desde
            <input
              type="date"
              value={form.fechaInicio}
              onChange={event => {
                setForm(current => ({
                  ...current,
                  fechaInicio: event.target.value
                }));
              }}
            />
          </label>

          <label>
            Hasta
            <input
              type="date"
              value={form.fechaFin}
              onChange={event => {
                setForm(current => ({
                  ...current,
                  fechaFin: event.target.value
                }));
              }}
            />
          </label>

          <button
            type="submit"
            className="operator-primary"
            disabled={loading || savingId !== null}
          >
            Aplicar filtros
          </button>
        </form>

        <div className="operator-actions">
          <span>
            {pagination
              ? `${pagination.totalRegistros} pedidos encontrados`
              : "Consultando pedidos"}
          </span>

          <button
            type="button"
            className="operator-refresh"
            disabled={loading || savingId !== null}
            onClick={() => {
              setReload(value => value + 1);
            }}
          >
            <RefreshCw size={16} />
            Actualizar
          </button>
        </div>

        {actionError && (
          <p
            className="cart-feedback error"
            role="alert"
          >
            {actionError}
          </p>
        )}

        {notice && (
          <p
            className="cart-feedback success"
            role="status"
          >
            {notice}
          </p>
        )}

        {/* ESTADOS DE CONSULTA */}

        {loading ? (
          <section
            className="operator-empty"
            role="status"
          >
            <span className="auth-spinner" />
            <p>Cargando pedidos...</p>
          </section>

        ) : listError ? (
          <section
            className="operator-empty"
            role="alert"
          >
            <h2>Error al consultar pedidos</h2>
            <p>{listError}</p>

            <button
              type="button"
              className="operator-primary"
              onClick={() => {
                setReload(value => value + 1);
              }}
            >
              Reintentar
            </button>
          </section>

        ) : orders.length === 0 ? (
          <section className="operator-empty">
            <ClipboardList size={42} />
            <h2>No se encontraron pedidos</h2>
            <p>
              Puedes modificar los filtros
              para consultar otros registros.
            </p>
          </section>

        ) : (
          <section
            className="operator-order-list"
            aria-label="Listado de pedidos"
          >
            {orders.map(order => {
              const next = nextOrderStatus(
                order.estado
              );

              const isSaving =
                savingId === order.idPedido;

              return (
                <article
                  className="operator-order-card"
                  key={order.idPedido}
                >
                  <div className="operator-order-top">
                    <div>
                      <span className="order-kicker">
                        PEDIDO #{order.idPedido}
                      </span>

                      <h2>
                        Cliente #{order.idUsuario}
                      </h2>

                      <small>
                        {formatOrderDate(
                          order.fechaCreacion
                        )}
                      </small>
                    </div>

                    <span
                      className={
                        `order-status status-${order.estado.toLowerCase()}`
                      }
                    >
                      {orderStatusLabel(
                        order.estado
                      )}
                    </span>
                  </div>

                  <div className="operator-order-numbers">
                    <div>
                      <small>Total del pedido</small>
                      <strong>
                        {formatGTQ(order.total)}
                      </strong>
                    </div>

                    <div>
                      <small>Reembolsado</small>
                      <strong>
                        {formatGTQ(
                          order.montoDevuelto
                        )}
                      </strong>
                    </div>

                    <div>
                      <small>Venta neta</small>
                      <strong>
                        {formatGTQ(
                          order.ventaNeta
                        )}
                      </strong>
                    </div>
                  </div>

                  {next ? (
                    <div className="operator-order-action">
                      <label
                        htmlFor={
                          `observation-${order.idPedido}`
                        }
                      >
                        Observación (opcional)
                      </label>

                      <textarea
                        id={
                          `observation-${order.idPedido}`
                        }
                        rows={2}
                        maxLength={300}
                        placeholder={
                          "Agrega una observación " +
                          "para el historial"
                        }
                        disabled={
                          savingId !== null || loading
                        }
                        value={
                          observations[order.idPedido]
                          ?? ""
                        }
                        onChange={event => {
                          setObservations(current => ({
                            ...current,
                            [order.idPedido]:
                              event.target.value
                          }));
                        }}
                      />

                      <button
                        type="button"
                        className="operator-primary"
                        disabled={
                          savingId !== null || loading
                        }
                        onClick={() => {
                          void handleAdvance(order);
                        }}
                      >
                        <Truck size={17} />

                        {isSaving
                          ? "Guardando..."
                          : `Pasar a ${orderStatusLabel(next)}`}

                        <ArrowRight size={16} />
                      </button>
                    </div>
                  ) : (
                    <p className="operator-final-state">
                      Este pedido no tiene una transición
                      operativa disponible.
                    </p>
                  )}
                </article>
              );
            })}
          </section>
        )}

        {/* PAGINACION */}

        {!loading &&
          !listError &&
          pagination &&
          pagination.totalPaginas > 1 && (
            <nav
              className="orders-pagination"
              aria-label="Páginas de pedidos"
            >
              <button
                type="button"
                disabled={
                  filters.pagina <= 1 ||
                  savingId !== null
                }
                onClick={() => {
                  setFilters(current => ({
                    ...current,
                    pagina: current.pagina - 1
                  }));
                }}
              >
                Anterior
              </button>

              <span>
                Página {pagination.pagina}
                {" "}de{" "}
                {pagination.totalPaginas}
              </span>

              <button
                type="button"
                disabled={
                  filters.pagina >=
                    pagination.totalPaginas ||
                  savingId !== null
                }
                onClick={() => {
                  setFilters(current => ({
                    ...current,
                    pagina: current.pagina + 1
                  }));
                }}
              >
                Siguiente
              </button>
            </nav>
          )}

      </div>
    </main>
  );
}
