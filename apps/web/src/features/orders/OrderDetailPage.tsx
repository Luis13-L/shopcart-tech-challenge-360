import {
  useEffect,
  useState,
  type FormEvent
} from "react";

import {
  ArrowLeft,
  CalendarClock,
  MapPin,
  Package,
  RefreshCw,
  ShieldCheck,
  Truck
} from "lucide-react";

import {
  Link,
  useParams
} from "react-router";

import { formatGTQ } from "../../lib/catalog";

import {
  cancelMyOrder,
  formatOrderDate,
  getMyOrder,
  orderStatusLabel,
  type OrderDetail
} from "./orders.api";

import {
  ReturnOrderPanel
} from "./ReturnOrderPanel";

export function OrderDetailPage() {
  const { id } = useParams();

  const [order, setOrder] =
    useState<OrderDetail | null>(null);

  const [loading, setLoading] = useState(true);

  const [error, setError] =
    useState<string | null>(null);

  const [notice, setNotice] =
    useState<string | null>(null);

  const [retry, setRetry] = useState(0);

  const [showCancel, setShowCancel] =
    useState(false);

  const [reason, setReason] = useState("");

  const [cancelling, setCancelling] =
    useState(false);

  // ========================================
  // CONSULTAR DETALLE DEL PEDIDO
  // ========================================

  useEffect(() => {
    const controller = new AbortController();

    if (
      !id ||
      !/^[1-9]\d{0,18}$/.test(id)
    ) {
      setLoading(false);
      setError("Identificador de pedido inválido");
      return;
    }

    setLoading(true);
    setError(null);

    getMyOrder(id, controller.signal)
      .then(data => {
        if (!controller.signal.aborted) {
          setOrder(data);
        }
      })
      .catch((cause: unknown) => {
        if (!controller.signal.aborted) {
          setError(
            cause instanceof Error
              ? cause.message
              : "No se pudo consultar el pedido"
          );
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [id, retry]);

  // ========================================
  // CANCELACION DEL PEDIDO
  // ========================================

  async function handleCancel(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();

    if (
      !order ||
      cancelling ||
      reason.trim().length === 0 ||
      reason.trim().length > 200
    ) {
      return;
    }

    setCancelling(true);
    setError(null);
    setNotice(null);

    try {
      const result = await cancelMyOrder(
        order.idPedido,
        reason
      );

      // Consultamos nuevamente el servidor.
      // No alteramos el estado local de forma
      // optimista.
      const updated = await getMyOrder(
        order.idPedido
      );

      setOrder(updated);
      setShowCancel(false);
      setReason("");

      setNotice(
        result.yaCancelado
          ? "El pedido ya estaba cancelado."
          : "Pedido cancelado correctamente."
      );

    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "No se pudo cancelar el pedido"
      );
    } finally {
      setCancelling(false);
    }
  }

  const canCancel =
    order !== null &&
    (
      order.estado === "PAGADO" ||
      order.estado === "PREPARANDO"
    );

  // ========================================
  // ESTADOS DE PANTALLA
  // ========================================

  if (loading) {
    return (
      <main
        className="orders-state orders-full-state"
        role="status"
      >
        <span className="auth-spinner" />
        <p>Consultando detalle del pedido...</p>
      </main>
    );
  }

  if (!order) {
    return (
      <main className="orders-state orders-full-state">
        <Package size={46} />

        <h1>No pudimos mostrar el pedido</h1>

        <p>{error || "Pedido no encontrado"}</p>

        <button
          type="button"
          className="btn btn-outline"
          onClick={() => {
            setRetry(value => value + 1);
          }}
        >
          Reintentar
        </button>

        <Link
          to="/mis-pedidos"
          className="btn btn-primary"
        >
          Volver a mis pedidos
        </Link>
      </main>
    );
  }

  // ========================================
  // DETALLE
  // ========================================

  return (
    <main className="orders-page">
      <div className="orders-container">

        <Link
          to="/mis-pedidos"
          className="orders-back"
        >
          <ArrowLeft size={18} />
          Todos mis pedidos
        </Link>

        <header className="orders-heading">
          <div>
            <span className="eyebrow">
              DETALLE DE COMPRA
            </span>

            <h1>
              Pedido <em>#{order.idPedido}</em>
            </h1>

            <p>
              Realizado el
              {" "}
              {formatOrderDate(order.fechaCreacion)}
            </p>
          </div>

          <span
            className={
              `order-status status-${order.estado.toLowerCase()}`
            }
          >
            {orderStatusLabel(order.estado)}
          </span>
        </header>

        {error && (
          <div
            className="cart-feedback error"
            role="alert"
          >
            {error}
          </div>
        )}

        {notice && (
          <div
            className="cart-feedback success"
            role="status"
          >
            {notice}
          </div>
        )}

        <div className="order-detail-layout">

          <div className="order-detail-main">

            {/* PRODUCTOS DEL PEDIDO */}

            <section className="orders-panel order-section">
              <div className="order-section-title">
                <Package size={22} />
                <h2>Productos comprados</h2>
              </div>

              {order.productos.map(product => (
                <article
                  className="order-product-row"
                  key={product.idDetallePedido}
                >
                  <div className="order-product-icon">
                    <Package size={25} />
                  </div>

                  <div>
                    <span className="order-kicker">
                      SKU · {product.sku}
                    </span>

                    <h3>
                      {product.nombreProducto}
                    </h3>

                    <small>
                      {product.cantidad}
                      {" "}
                      ×
                      {" "}
                      {formatGTQ(
                        product.precioUnitario
                      )}
                    </small>

                    {product.cantidadDevuelta > 0 && (
                      <small>
                        Unidades devueltas:
                        {" "}
                        {product.cantidadDevuelta}
                      </small>
                    )}
                  </div>

                  <strong>
                    {formatGTQ(
                      product.importeLinea
                    )}
                  </strong>
                </article>
              ))}
            </section>

            {/* DIRECCION HISTORICA */}

            <section className="orders-panel order-section">
              <div className="order-section-title">
                <MapPin size={22} />
                <h2>Dirección de entrega</h2>
              </div>

              <div className="order-address">
                <strong>
                  {order.direccionEntrega.destinatario}
                </strong>

                <p>
                  {order.direccionEntrega.direccionLinea1}
                  <br />
                  {order.direccionEntrega.municipio},
                  {" "}
                  {order.direccionEntrega.departamento}
                </p>

                <p>
                  Teléfono:
                  {" "}
                  {order.direccionEntrega.telefono}
                </p>

                {order.direccionEntrega.referencia && (
                  <p>
                    Referencia:
                    {" "}
                    {order.direccionEntrega.referencia}
                  </p>
                )}
              </div>
            </section>

            {/* HISTORIAL DE ESTADOS */}

            <section className="orders-panel order-section">
              <div className="order-section-title">
                <CalendarClock size={22} />
                <h2>Historial de estados</h2>
              </div>

              <ol className="order-timeline">
                {order.historial.map(item => (
                  <li key={item.idHistorialPedido}>
                    <span className="order-timeline-dot" />

                    <div>
                      <strong>
                        {orderStatusLabel(
                          item.estadoNuevo
                        )}
                      </strong>

                      <small>
                        {formatOrderDate(
                          item.fechaCambio
                        )}
                      </small>

                      {item.observacion && (
                        <p>{item.observacion}</p>
                      )}
                    </div>
                  </li>
                ))}
              </ol>
            </section>
          </div>

          {/* RESUMEN Y OPERACIONES */}

          <aside className="order-detail-aside">

            <section className="orders-panel order-section">
              <div className="order-section-title">
                <Truck size={22} />
                <h2>Resumen</h2>
              </div>

              <div className="order-totals-row">
                <span>Subtotal</span>
                <strong>
                  {formatGTQ(order.subtotal)}
                </strong>
              </div>

              <div className="order-totals-row">
                <span>Descuento</span>
                <strong>
                  {formatGTQ(order.descuento)}
                </strong>
              </div>

              {order.codigoCupon && (
                <div className="order-totals-row">
                  <span>Cupón</span>
                  <strong>
                    {order.codigoCupon}
                  </strong>
                </div>
              )}

              <div className="order-totals-total">
                <span>Total</span>

                <strong>
                  {formatGTQ(order.total)}
                </strong>
              </div>

              <div className="order-secure-note">
                <ShieldCheck size={18} />

                <span>
                  Datos consultados desde
                  tu historial de compras.
                </span>
              </div>
            </section>

            {/* CANCELAR ANTES DEL DESPACHO */}

            {canCancel && (
              <section className="orders-panel order-section">
                <div className="order-section-title">
                  <RefreshCw size={21} />
                  <h2>Cancelar pedido</h2>
                </div>

                <p className="order-action-help">
                  Puedes solicitar la cancelación
                  mientras el pedido no haya
                  sido despachado.
                </p>

                {!showCancel ? (
                  <button
                    className="order-danger-button"
                    type="button"
                    onClick={() => {
                      setShowCancel(true);
                    }}
                  >
                    Solicitar cancelación
                  </button>
                ) : (
                  <form
                    className="order-cancel-form"
                    onSubmit={event => {
                      void handleCancel(event);
                    }}
                  >
                    <label htmlFor="cancel-reason">
                      Motivo de cancelación
                    </label>

                    <textarea
                      id="cancel-reason"
                      required
                      maxLength={200}
                      rows={4}
                      placeholder="Explica brevemente el motivo..."
                      value={reason}
                      onChange={event => {
                        setReason(event.target.value);
                      }}
                    />

                    <button
                      className="order-danger-button"
                      type="submit"
                      disabled={
                        cancelling ||
                        reason.trim().length === 0
                      }
                    >
                      {cancelling
                        ? "Cancelando..."
                        : "Confirmar cancelación"}
                    </button>

                    <button
                      type="button"
                      className="order-secondary-button"
                      disabled={cancelling}
                      onClick={() => {
                        setShowCancel(false);
                        setReason("");
                      }}
                    >
                      Mantener mi pedido
                    </button>
                  </form>
                )}
              </section>
            )}

            
                {/* DEVOLUCIONES DESPUES DE LA ENTREGA */}

                {(
                order.estado === "ENTREGADO" ||
                order.estado === "DEVUELTO_PARCIAL"
                ) && order.productos.some(
                item => item.cantidad > item.cantidadDevuelta
                ) && (
                <ReturnOrderPanel
                    order={order}
                    onCompleted={result => {

                    setNotice(
                        result.reutilizado
                        ? `Devolución #${result.idDevolucion} recuperada. Reembolso simulado: ${formatGTQ(result.montoReembolso)}.`
                        : `Devolución #${result.idDevolucion} procesada. Reembolso simulado: ${formatGTQ(result.montoReembolso)}.`
                    );

                    // Volvemos a consultar SQL Server:
                    // estado, cantidades e historial.
                    setRetry(value => value + 1);

                    }}
                />
                )}

          </aside>
        </div>
      </div>
    </main>
  );
}
