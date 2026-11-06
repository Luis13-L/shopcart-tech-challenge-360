import {
  useEffect,
  useState
} from "react";

import {
  ArrowLeft,
  ArrowRight,
  ChevronLeft,
  ChevronRight,
  PackageSearch,
  RefreshCw,
  ShoppingBag
} from "lucide-react";

import { Link } from "react-router";

import { formatGTQ } from "../../lib/catalog";

import {
  formatOrderDate,
  getMyOrders,
  orderStatusLabel,
  type OrderStatus,
  type OrdersResult
} from "./orders.api";

const statuses: OrderStatus[] = [
  "PAGADO",
  "PREPARANDO",
  "DESPACHADO",
  "ENTREGADO",
  "CANCELADO",
  "DEVUELTO_PARCIAL",
  "DEVUELTO_TOTAL"
];

export function OrdersPage() {
  const [status, setStatus] =
    useState<OrderStatus | "">("");

  const [page, setPage] = useState(1);

  const [result, setResult] =
    useState<OrdersResult | null>(null);

  const [loading, setLoading] = useState(true);

  const [error, setError] =
    useState<string | null>(null);

  const [retry, setRetry] = useState(0);

  useEffect(() => {
    const controller = new AbortController();

    setLoading(true);
    setError(null);

    getMyOrders(
      page,
      status,
      controller.signal
    )
      .then(data => {
        if (!controller.signal.aborted) {
          setResult(data);
        }
      })
      .catch((cause: unknown) => {
        if (!controller.signal.aborted) {
          setError(
            cause instanceof Error
              ? cause.message
              : "No fue posible consultar los pedidos"
          );
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [page, status, retry]);

  const orders = result?.items ?? [];
  const pagination = result?.pagination;

  return (
    <main className="orders-page">
      <div className="orders-container">

        <Link
          to="/mi-cuenta"
          className="orders-back"
        >
          <ArrowLeft size={18} />
          Volver a mi cuenta
        </Link>

        <header className="orders-heading">
          <div>
            <span className="eyebrow">
              MI ACTIVIDAD
            </span>

            <h1>
              Mis <em>pedidos.</em>
            </h1>

            <p>
              Consulta tus compras y realiza
              el seguimiento de cada pedido.
            </p>
          </div>

          <ShoppingBag size={39} />
        </header>

        <section className="orders-panel">
          <div className="orders-toolbar">

            <label>
              Estado del pedido

              <select
                value={status}
                onChange={event => {
                  setStatus(
                    event.target.value as OrderStatus | ""
                  );
                  setPage(1);
                }}
              >
                <option value="">
                  Todos los estados
                </option>

                {statuses.map(value => (
                  <option
                    key={value}
                    value={value}
                  >
                    {orderStatusLabel(value)}
                  </option>
                ))}
              </select>
            </label>

            <button
              type="button"
              className="orders-refresh"
              disabled={loading}
              onClick={() => {
                setRetry(value => value + 1);
              }}
            >
              <RefreshCw size={17} />
              Actualizar
            </button>
          </div>

          {loading ? (
            <div
              className="orders-state"
              role="status"
            >
              <span className="auth-spinner" />
              <p>Cargando tus pedidos...</p>
            </div>

          ) : error ? (
            <div
              className="orders-state"
              role="alert"
            >
              <PackageSearch size={43} />
              <h2>No pudimos cargar los pedidos</h2>
              <p>{error}</p>

              <button
                className="btn btn-primary"
                type="button"
                onClick={() => {
                  setRetry(value => value + 1);
                }}
              >
                Intentar nuevamente
              </button>
            </div>

          ) : orders.length === 0 ? (
            <div className="orders-state">
              <PackageSearch size={43} />

              <h2>No hay pedidos para mostrar</h2>

              <p>
                {status
                  ? "Prueba con otro filtro."
                  : "Cuando completes una compra, aparecerá aquí."}
              </p>

              <Link
                to="/"
                className="btn btn-primary"
              >
                Explorar productos
              </Link>
            </div>

          ) : (
            <>
              <div className="orders-list">

                {orders.map(order => (
                  <article
                    className="order-card"
                    key={order.idPedido}
                  >
                    <div className="order-card-top">
                      <div>
                        <span className="order-kicker">
                          NÚMERO DE PEDIDO
                        </span>

                        <h2>#{order.idPedido}</h2>
                      </div>

                      <span
                        className={
                          `order-status status-${order.estado.toLowerCase()}`
                        }
                      >
                        {orderStatusLabel(order.estado)}
                      </span>
                    </div>

                    <div className="order-card-info">
                      <div>
                        <small>Fecha de compra</small>
                        <strong>
                          {formatOrderDate(
                            order.fechaCreacion
                          )}
                        </strong>
                      </div>

                      <div>
                        <small>Total</small>
                        <strong>
                          {formatGTQ(order.total)}
                        </strong>
                      </div>

                      <div>
                        <small>Cupón</small>
                        <strong>
                          {order.codigoCupon || "Sin cupón"}
                        </strong>
                      </div>
                    </div>

                    <Link
                      className="order-detail-link"
                      to={`/mis-pedidos/${order.idPedido}`}
                    >
                      Ver detalle
                      <ArrowRight size={17} />
                    </Link>
                  </article>
                ))}

              </div>

              {pagination &&
                pagination.totalPaginas > 1 && (
                <nav
                  className="orders-pagination"
                  aria-label="Paginación de pedidos"
                >
                  <button
                    type="button"
                    disabled={page <= 1}
                    onClick={() => {
                      setPage(value => value - 1);
                    }}
                  >
                    <ChevronLeft size={17} />
                    Anterior
                  </button>

                  <span>
                    Página {pagination.pagina} de
                    {" "}
                    {pagination.totalPaginas}
                  </span>

                  <button
                    type="button"
                    disabled={
                      page >= pagination.totalPaginas
                    }
                    onClick={() => {
                      setPage(value => value + 1);
                    }}
                  >
                    Siguiente
                    <ChevronRight size={17} />
                  </button>
                </nav>
              )}
            </>
          )}
        </section>
      </div>
    </main>
  );
}
