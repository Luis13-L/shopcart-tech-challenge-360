import {
  ArrowRight,
  CheckCircle2,
  ShieldCheck,
  ShoppingBag
} from "lucide-react";

import {
  Link,
  useLocation
} from "react-router";

import { formatGTQ } from "../../lib/catalog";

import type {
  CheckoutResult
} from "./checkout.api";

export function OrderSuccessPage() {
  const location = useLocation();

  const state = location.state as {
    order?: CheckoutResult;
  } | null;

  const order = state?.order;

  if (!order) {
    return (
      <main className="checkout-loading">
        <ShoppingBag size={46} />

        <h1>Consulta tus pedidos</h1>

        <p>
          No encontramos una confirmación de compra
          asociada a esta vista. Si ya completaste
          una compra, consulta su estado en tu historial.
        </p>

        <Link to="/mi-cuenta" className="btn btn-primary">
          Ir a mi cuenta
        </Link>
      </main>
    );
  }

  return (
    <main className="order-success-page">
      <section className="order-success-card">

        <div className="order-success-icon">
          <CheckCircle2 size={45} />
        </div>

        <span className="eyebrow">
          COMPRA CONFIRMADA
        </span>

        <h1>
          ¡Tu pedido está listo!
        </h1>

        <p>
          ShopCart registró correctamente
          tu pedido con pago simulado.
        </p>

        <div className="order-success-details">
          <div>
            <span>Número de pedido</span>
            <strong>#{order.idPedido}</strong>
          </div>

          <div>
            <span>Estado</span>
            <strong>{order.estado}</strong>
          </div>

          <div>
            <span>Subtotal</span>
            <strong>
              {formatGTQ(order.subtotal)}
            </strong>
          </div>

          <div>
            <span>Descuento</span>
            <strong>
              {formatGTQ(order.descuento)}
            </strong>
          </div>

          <div className="order-success-total">
            <span>Total pagado (simulado)</span>
            <strong>
              {formatGTQ(order.total)}
            </strong>
          </div>
        </div>

        <div className="order-success-security">
          <ShieldCheck size={20} />
          <span>
            Pedido registrado con validaciones de
            inventario e idempotencia.
          </span>
        </div>

        <Link
          to="/"
          className="btn btn-primary"
        >
          Seguir comprando
          <ArrowRight size={18} />
        </Link>

      </section>
    </main>
  );
}
