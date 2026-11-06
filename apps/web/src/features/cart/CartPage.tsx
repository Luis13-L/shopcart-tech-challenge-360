import { useState } from "react";

import {
  ArrowLeft,
  ArrowRight,
  Box,
  Minus,
  Plus,
  RefreshCw,
  ShieldCheck,
  ShoppingBag,
  Trash2
} from "lucide-react";

import { Link } from "react-router";

import { formatGTQ } from "../../lib/catalog";
import { useCart } from "./CartProvider";

import type {
  CartItem
} from "./cart.api";

// ==========================================
// IMAGEN CON REPRESENTACION ALTERNATIVA
// ==========================================

function CartProductImage({
  item
}: {
  item: CartItem;
}) {

  const [failed, setFailed] = useState(false);

  if (failed) {
    return (
      <div className="cart-image-fallback">
        <Box size={39} strokeWidth={1.3} />
      </div>
    );
  }

  return (
    <img
      src={
        `/images/products/${encodeURIComponent(item.sku)}.webp`
      }
      alt={item.nombreProducto}
      onError={() => setFailed(true)}
      loading="lazy"
    />
  );
}

// ==========================================
// PAGINA PRINCIPAL
// ==========================================

export function CartPage() {

  const {
    cart,
    loading,
    busy,
    error,
    feedback,
    itemCount,
    refresh,
    setQuantity,
    remove
  } = useCart();

  const isEmpty =
    !cart || cart.items.length === 0;

  return (
    <main className="cart-page">

      <div className="cart-container">

        <div className="cart-top">

          <Link to="/" className="cart-back">
            <ArrowLeft size={18} />
            Continuar comprando
          </Link>

          <span className="cart-top-label">
            SHOPCART / MI COMPRA
          </span>

        </div>

        <div className="cart-heading">

          <div>
            <span className="eyebrow">
              TU SELECCIÓN
            </span>

            <h1>
              Mi <em>carrito.</em>
            </h1>

            <p>
              Revisa tus productos antes de
              continuar con la compra.
            </p>
          </div>

          <button
            type="button"
            className="cart-refresh"
            onClick={() => {
              void refresh();
            }}
            disabled={loading || busy}
          >
            <RefreshCw size={17} />
            Actualizar
          </button>

        </div>

        {/* MENSAJES DE OPERACIONES */}

        {feedback && (
          <div
            role="status"
            className={
              `cart-feedback ${feedback.type}`
            }
          >
            {feedback.message}
          </div>
        )}

        {/* CARGA INICIAL */}

        {loading ? (

          <section
            className="cart-empty"
            role="status"
          >
            <span className="auth-spinner" />
            <h2>Cargando carrito...</h2>
            <p>
              Consultando tus productos en ShopCart.
            </p>
          </section>

        ) : error ? (

          /* ERROR AL CARGAR */

          <section
            className="cart-empty"
            role="alert"
          >
            <RefreshCw size={48} />

            <h2>
              No pudimos consultar tu carrito
            </h2>

            <p>{error}</p>

            <button
              type="button"
              className="btn btn-primary"
              onClick={() => {
                void refresh();
              }}
            >
              Intentar nuevamente
            </button>
          </section>

        ) : isEmpty ? (

          /* CARRITO VACIO */

          <section className="cart-empty">

            <div className="cart-empty-icon">
              <ShoppingBag size={43} />
            </div>

            <h2>
              Tu carrito está esperando.
            </h2>

            <p>
              Descubre productos y agrega
              los que más te gusten.
            </p>

            <Link
              to="/#catalogo"
              className="btn btn-primary"
            >
              Explorar catálogo
              <ArrowRight size={18} />
            </Link>

          </section>

        ) : (

          /* CARRITO CON PRODUCTOS */

          <div className="cart-layout">

            <section
              className="cart-items-panel"
              aria-label="Productos del carrito"
            >

              <div className="cart-panel-heading">

                <h2>Productos seleccionados</h2>

                <span>
                  {itemCount}
                  {" "}
                  {itemCount === 1
                    ? "unidad"
                    : "unidades"}
                </span>

              </div>

              {cart.items.map((item) => (

                <article
                  className="cart-item"
                  key={item.idVariante}
                >

                  <div className="cart-item-image">
                    <CartProductImage item={item} />
                  </div>

                  <div className="cart-item-info">

                    <span className="cart-item-sku">
                      SKU · {item.sku}
                    </span>

                    <h3>
                      {item.nombreProducto}
                    </h3>

                    <span className="cart-item-price">
                      {formatGTQ(item.precioUnitario)}
                      {" "}
                      / unidad
                    </span>

                    <div className="cart-item-controls">

                      <div
                        className="cart-quantity"
                        aria-label={
                          `Cantidad de ${item.nombreProducto}`
                        }
                      >

                        <button
                          type="button"
                          aria-label={
                            `Disminuir cantidad de ${item.nombreProducto}`
                          }
                          disabled={busy}
                          onClick={() => {
                            void setQuantity(
                              item.idVariante,
                              item.cantidad - 1
                            );
                          }}
                        >
                          <Minus size={16} />
                        </button>

                        <output>
                          {item.cantidad}
                        </output>

                        <button
                          type="button"
                          aria-label={
                            `Aumentar cantidad de ${item.nombreProducto}`
                          }
                          disabled={busy}
                          onClick={() => {
                            void setQuantity(
                              item.idVariante,
                              item.cantidad + 1
                            );
                          }}
                        >
                          <Plus size={16} />
                        </button>

                      </div>

                      <button
                        className="cart-remove"
                        type="button"
                        disabled={busy}
                        onClick={() => {
                          void remove(item.idVariante);
                        }}
                      >
                        <Trash2 size={16} />
                        Eliminar
                      </button>

                    </div>

                  </div>

                  <strong className="cart-line-total">
                    {formatGTQ(item.importeLinea)}
                  </strong>

                </article>

              ))}

            </section>

            {/* RESUMEN DEL PEDIDO */}

            <aside
              className="cart-summary"
              aria-label="Resumen del carrito"
            >

              <span className="cart-summary-eyebrow">
                RESUMEN DE COMPRA
              </span>

              <h2>Tu pedido</h2>

              <div className="cart-summary-row">
                <span>Subtotal</span>
                <strong>
                  {formatGTQ(cart.subtotal)}
                </strong>
              </div>

              <div className="cart-summary-row">
                <span>Descuentos</span>
                <strong>
                  {formatGTQ(cart.descuento)}
                </strong>
              </div>

              <div className="cart-summary-divider" />

              <div className="cart-summary-total">
                <span>Total</span>

                <strong>
                  {formatGTQ(cart.total)}
                </strong>
              </div>

              <p className="cart-tax-note">
                Los precios publicados incluyen IVA.
                El total definitivo se verificará
                durante el checkout.
              </p>

              
                <Link
                to="/checkout"
                className="cart-checkout-button"
                >
                Continuar al checkout
                <ArrowRight size={19} />
                </Link>


              <p className="cart-next-note">
                Integraremos direcciones, cupones,
                reservas de inventario y confirmación
                de compra en el siguiente paso.
              </p>

              <div className="cart-summary-security">
                <ShieldCheck size={20} />

                <span>
                  Tus cantidades y totales se validan
                  en el servidor.
                </span>
              </div>

            </aside>

          </div>

        )}

      </div>
    </main>
  );
}
