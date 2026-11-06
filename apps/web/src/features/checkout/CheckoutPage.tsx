import {
  useEffect,
  useState,
  type FormEvent
} from "react";

import {
  ArrowLeft,
  ArrowRight,
  CheckCircle2,
  Clock3,
  CreditCard,
  MapPin,
  Plus,
  ShieldCheck
} from "lucide-react";

import {
  Link,
  useNavigate
} from "react-router";

import { formatGTQ } from "../../lib/catalog";
import { useCart } from "../cart/CartProvider";

import {
  createMyAddress,
  listMyAddresses,
  type Address,
  type CreateAddressInput
} from "./addresses.api";

import {
  reserveCheckout,
  confirmCheckout
} from "./checkout.api";

const EMPTY_ADDRESS: CreateAddressInput = {
  destinatario: "",
  telefono: "",
  departamento: "",
  municipio: "",
  direccionLinea1: "",
  referencia: null
};

interface ReservationAttempt {
  idReserva: string;
  claveIdempotencia: string;
}

function getErrorMessage(error: unknown): string {
  return error instanceof Error
    ? error.message
    : "No fue posible completar la operacion";
}

export function CheckoutPage() {
  const navigate = useNavigate();

  const {
    cart,
    loading: cartLoading,
    busy: cartBusy,
    error: cartError,
    refresh
  } = useCart();

  const [addresses, setAddresses] =
    useState<Address[]>([]);

  const [loadingAddresses, setLoadingAddresses] =
    useState(true);

  const [selectedAddressId, setSelectedAddressId] =
    useState<number | null>(null);

  const [showAddressForm, setShowAddressForm] =
    useState(false);

  const [form, setForm] =
    useState<CreateAddressInput>(EMPTY_ADDRESS);

  const [savingAddress, setSavingAddress] =
    useState(false);

  const [reserving, setReserving] =
    useState(false);

  const [confirming, setConfirming] =
    useState(false);

  const [reservation, setReservation] =
    useState<ReservationAttempt | null>(null);

  const [error, setError] =
    useState<string | null>(null);

  const [message, setMessage] =
    useState<string | null>(null);

  // ========================================
  // 1. CONSULTAR DIRECCIONES DEL CLIENTE
  // ========================================

  useEffect(() => {
    let active = true;

    listMyAddresses()
      .then((data) => {
        if (!active) return;

        const enabled = data.filter(
          address => address.activa
        );

        setAddresses(enabled);

        setSelectedAddressId(current => {
          if (
            current !== null &&
            enabled.some(
              address => address.idDireccion === current
            )
          ) {
            return current;
          }

          return enabled[0]?.idDireccion ?? null;
        });

        if (enabled.length === 0) {
          setShowAddressForm(true);
        }
      })
      .catch((cause: unknown) => {
        if (active) {
          setError(getErrorMessage(cause));
        }
      })
      .finally(() => {
        if (active) {
          setLoadingAddresses(false);
        }
      });

    return () => {
      active = false;
    };
  }, []);

  // ========================================
  // 2. ACTUALIZAR CAMPOS DEL FORMULARIO
  // ========================================

  function changeField(
    name: keyof CreateAddressInput,
    value: string
  ): void {
    setForm(current => ({
      ...current,
      [name]: value
    }));
  }

  // ========================================
  // 3. CREAR DIRECCION
  // ========================================

  async function handleCreateAddress(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();

    if (savingAddress || reservation) return;

    setSavingAddress(true);
    setError(null);
    setMessage(null);

    try {
      const newAddress = await createMyAddress({
        destinatario: form.destinatario.trim(),
        telefono: form.telefono.trim(),
        departamento: form.departamento.trim(),
        municipio: form.municipio.trim(),
        direccionLinea1: form.direccionLinea1.trim(),
        referencia: form.referencia?.trim() || null
      });

      setAddresses(current => [
        ...current,
        newAddress
      ]);

      setSelectedAddressId(newAddress.idDireccion);

      setForm(EMPTY_ADDRESS);
      setShowAddressForm(false);

      setMessage("Dirección registrada correctamente");

    } catch (cause) {
      setError(getErrorMessage(cause));
    } finally {
      setSavingAddress(false);
    }
  }

  // ========================================
  // 4. RESERVAR INVENTARIO
  // ========================================

  async function handleReserve(): Promise<void> {
    if (
      reserving ||
      confirming ||
      !cart ||
      cart.items.length === 0 ||
      cartLoading ||
      cartBusy
    ) {
      return;
    }

    if (selectedAddressId === null) {
      setError("Selecciona una dirección de entrega");
      return;
    }

    setReserving(true);
    setError(null);
    setMessage(null);

    try {
      const data = await reserveCheckout(
        cart.idCarrito
      );

      // La misma reserva siempre debe
      // reutilizar la misma clave.
      const storageKey =
        `shopcart:checkout:${data.idReserva}`;

      const stored = window.sessionStorage.getItem(
        storageKey
      );

      const key =
        stored && /^[a-zA-Z0-9_-]{16,100}$/.test(stored)
          ? stored
          : crypto.randomUUID();

      window.sessionStorage.setItem(
        storageKey,
        key
      );

      setReservation({
        idReserva: data.idReserva,
        claveIdempotencia: key
      });

      setMessage(
        "Inventario reservado. La reserva es válida durante 15 minutos desde su creación."
      );

    } catch (cause) {
      setError(getErrorMessage(cause));
    } finally {
      setReserving(false);
    }
  }

  // ========================================
  // 5. CONFIRMAR CHECKOUT
  // ========================================

  async function handleConfirm(): Promise<void> {
    if (
      !reservation ||
      selectedAddressId === null ||
      !cart ||
      confirming
    ) {
      return;
    }

    setConfirming(true);
    setError(null);
    setMessage(null);

    try {
      const result = await confirmCheckout({
        idReserva: reservation.idReserva,
        idDireccion: selectedAddressId,
        claveIdempotencia:
          reservation.claveIdempotencia,
        totalEsperado: cart.total
      });

      // El pedido se confirmó o se recuperó
      // mediante la misma clave idempotente.
      window.sessionStorage.removeItem(
        `shopcart:checkout:${reservation.idReserva}`
      );

      navigate("/pedido-confirmado", {
        replace: true,
        state: {
          order: result
        }
      });

      // Recuperar el nuevo carrito activo.
      void refresh();

    } catch (cause) {
      // Mantenemos la reserva y la clave.
      // Un reintento debe enviar el mismo
      // identificador de idempotencia.
      setError(getErrorMessage(cause));
    } finally {
      setConfirming(false);
    }
  }

  const isCartEmpty =
    !cart || cart.items.length === 0;

  const isBusy =
    savingAddress ||
    reserving ||
    confirming ||
    cartBusy;

  // ========================================
  // 6. ESTADOS DE CARGA Y ERROR
  // ========================================

  if (cartLoading || loadingAddresses) {
    return (
      <main className="checkout-loading" role="status">
        <span className="auth-spinner" />
        <p>Preparando tu compra...</p>
      </main>
    );
  }

  if (cartError) {
    return (
      <main className="checkout-loading">
        <h2>No pudimos cargar el carrito</h2>
        <p>{cartError}</p>
        <Link to="/carrito" className="btn btn-primary">
          Volver al carrito
        </Link>
      </main>
    );
  }

  if (isCartEmpty) {
    return (
      <main className="checkout-loading">
        <h2>Tu carrito está vacío</h2>
        <p>Agrega productos antes de comprar.</p>
        <Link to="/" className="btn btn-primary">
          Explorar productos
        </Link>
      </main>
    );
  }

  // ========================================
  // 7. PANTALLA DE CHECKOUT
  // ========================================

  return (
    <main className="checkout-page">
      <div className="checkout-container">

        <Link to="/carrito" className="cart-back">
          <ArrowLeft size={18} />
          Volver al carrito
        </Link>

        <header className="checkout-heading">
          <span className="eyebrow">
            ÚLTIMO PASO
          </span>

          <h1>
            Finaliza tu <em>compra.</em>
          </h1>

          <p>
            Confirma la dirección y reserva tus
            productos antes de completar el pedido.
          </p>
        </header>

        <div className="checkout-steps">
          <span>
            <MapPin size={16} />
            1. Dirección
          </span>
          <span>
            <Clock3 size={16} />
            2. Reserva
          </span>
          <span>
            <CreditCard size={16} />
            3. Confirmación
          </span>
        </div>

        {error && (
          <div className="cart-feedback error" role="alert">
            {error}
          </div>
        )}

        {message && (
          <div className="cart-feedback success" role="status">
            {message}
          </div>
        )}

        <div className="checkout-layout">

          <div className="checkout-main">

            {/* DIRECCIONES */}

            <section className="checkout-card">
              <div className="checkout-section-header">
                <div>
                  <span className="checkout-step-number">
                    01
                  </span>

                  <h2>Dirección de entrega</h2>
                </div>

                <MapPin size={22} />
              </div>

              {addresses.length > 0 && (
                <div className="checkout-address-list">
                  {addresses.map(address => (
                    <button
                      type="button"
                      key={address.idDireccion}
                      className={
                        selectedAddressId === address.idDireccion
                          ? "checkout-address-option selected"
                          : "checkout-address-option"
                      }
                      aria-pressed={
                        selectedAddressId === address.idDireccion
                      }
                      disabled={reservation !== null}
                      onClick={() => {
                        setSelectedAddressId(
                          address.idDireccion
                        );
                      }}
                    >
                      <span className="checkout-address-radio" />

                      <span>
                        <strong>
                          {address.destinatario}
                        </strong>

                        <small>
                          {address.direccionLinea1},
                          {" "}
                          {address.municipio},
                          {" "}
                          {address.departamento}
                        </small>

                        <small>
                          Tel. {address.telefono}
                        </small>

                        {address.referencia && (
                          <small>
                            Ref.: {address.referencia}
                          </small>
                        )}
                      </span>
                    </button>
                  ))}
                </div>
              )}

              {!reservation && (
                <button
                  type="button"
                  className="checkout-add-address"
                  onClick={() => {
                    setShowAddressForm(value => !value);
                  }}
                >
                  <Plus size={17} />
                  {showAddressForm
                    ? "Cerrar formulario"
                    : "Agregar dirección"}
                </button>
              )}

              {showAddressForm && !reservation && (
                <form
                  className="checkout-address-form"
                  onSubmit={event => {
                    void handleCreateAddress(event);
                  }}
                >
                  <label>
                    Destinatario
                    <input
                      required
                      minLength={3}
                      maxLength={150}
                      value={form.destinatario}
                      onChange={event =>
                        changeField(
                          "destinatario",
                          event.target.value
                        )
                      }
                      placeholder="Nombre de quien recibe"
                    />
                  </label>

                  <label>
                    Teléfono
                    <input
                      required
                      minLength={8}
                      maxLength={25}
                      value={form.telefono}
                      onChange={event =>
                        changeField(
                          "telefono",
                          event.target.value
                        )
                      }
                      placeholder="Número de contacto"
                    />
                  </label>

                  <label>
                    Departamento
                    <input
                      required
                      minLength={2}
                      maxLength={100}
                      value={form.departamento}
                      onChange={event =>
                        changeField(
                          "departamento",
                          event.target.value
                        )
                      }
                      placeholder="Ej. Sololá"
                    />
                  </label>

                  <label>
                    Municipio
                    <input
                      required
                      minLength={2}
                      maxLength={100}
                      value={form.municipio}
                      onChange={event =>
                        changeField(
                          "municipio",
                          event.target.value
                        )
                      }
                      placeholder="Ej. Sololá"
                    />
                  </label>

                  <label className="checkout-full-field">
                    Dirección exacta
                    <input
                      required
                      minLength={5}
                      maxLength={250}
                      value={form.direccionLinea1}
                      onChange={event =>
                        changeField(
                          "direccionLinea1",
                          event.target.value
                        )
                      }
                      placeholder="Zona, calle, avenida, número..."
                    />
                  </label>

                  <label className="checkout-full-field">
                    Referencia (opcional)
                    <input
                      maxLength={250}
                      value={form.referencia ?? ""}
                      onChange={event =>
                        changeField(
                          "referencia",
                          event.target.value
                        )
                      }
                      placeholder="Casa de color..., portón..."
                    />
                  </label>

                  <button
                    type="submit"
                    className="btn btn-primary checkout-full-field"
                    disabled={savingAddress}
                  >
                    {savingAddress
                      ? "Guardando dirección..."
                      : "Guardar dirección"}

                    <ArrowRight size={17} />
                  </button>
                </form>
              )}
            </section>

            {/* RESERVA */}

            <section className="checkout-card">
              <div className="checkout-section-header">
                <div>
                  <span className="checkout-step-number">
                    02
                  </span>
                  <h2>Reserva de inventario</h2>
                </div>

                <Clock3 size={22} />
              </div>

              <p className="checkout-description">
                Antes de confirmar, ShopCart verifica
                que haya existencias disponibles y
                reserva temporalmente tus productos.
              </p>

              {reservation ? (
                <div className="checkout-reserved">
                  <CheckCircle2 size={23} />
                  <div>
                    <strong>Reserva preparada</strong>
                    <small>
                      Referencia: {reservation.idReserva}
                    </small>
                    <small>
                      La reserva dura 15 minutos desde
                      su creación.
                    </small>
                  </div>
                </div>
              ) : (
                <button
                  type="button"
                  className="btn btn-primary"
                  disabled={
                    isBusy ||
                    selectedAddressId === null
                  }
                  onClick={() => {
                    void handleReserve();
                  }}
                >
                  {reserving
                    ? "Reservando productos..."
                    : "Reservar inventario"}

                  <ArrowRight size={17} />
                </button>
              )}
            </section>

            {/* PAGO SIMULADO */}

            <section className="checkout-card">
              <div className="checkout-section-header">
                <div>
                  <span className="checkout-step-number">
                    03
                  </span>
                  <h2>Confirmación</h2>
                </div>

                <CreditCard size={22} />
              </div>

              <p className="checkout-description">
                Esta demostración utiliza pago simulado.
                No se solicitarán datos de tarjetas
                ni se realizará un cargo bancario real.
              </p>

              <div className="checkout-payment-info">
                <ShieldCheck size={20} />
                <span>
                  El backend valida el total, registra
                  la compra de manera atómica y protege
                  los reintentos mediante idempotencia.
                </span>
              </div>

              <button
                type="button"
                className="checkout-confirm-button"
                disabled={
                  !reservation ||
                  selectedAddressId === null ||
                  isBusy
                }
                onClick={() => {
                  void handleConfirm();
                }}
              >
                {confirming
                  ? "Confirmando pedido..."
                  : "Confirmar pedido (pago simulado)"}

                <ArrowRight size={19} />
              </button>
            </section>
          </div>

          {/* RESUMEN */}

          <aside className="checkout-summary">
            <span className="checkout-summary-kicker">
              TU PEDIDO
            </span>

            <h2>Resumen de compra</h2>

            <div className="checkout-summary-items">
              {cart.items.map(item => (
                <div
                  key={item.idVariante}
                  className="checkout-summary-item"
                >
                  <span>
                    {item.cantidad} × {item.nombreProducto}
                  </span>

                  <strong>
                    {formatGTQ(item.importeLinea)}
                  </strong>
                </div>
              ))}
            </div>

            <div className="checkout-summary-row">
              <span>Subtotal</span>
              <strong>
                {formatGTQ(cart.subtotal)}
              </strong>
            </div>

            <div className="checkout-summary-row">
              <span>Descuento del carrito</span>
              <strong>
                {formatGTQ(cart.descuento)}
              </strong>
            </div>

            <div className="checkout-summary-total">
              <span>Total esperado</span>
              <strong>{formatGTQ(cart.total)}</strong>
            </div>

            <p className="checkout-summary-note">
              Montos en quetzales, IVA incluido.
              La confirmación volverá a verificar
              el total en SQL Server.
            </p>

            <p className="checkout-summary-note">
              Los cupones promocionales se integrarán
              con una cotización previa del servidor.
            </p>
          </aside>

        </div>
      </div>
    </main>
  );
}
