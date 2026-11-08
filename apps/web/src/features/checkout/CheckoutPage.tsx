import {
  useEffect,
  useRef,
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
  ShieldCheck,
  TicketPercent
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
  confirmCheckout,
  quoteCheckout,
  type CouponQuote
} from "./checkout.api";

const EMPTY_ADDRESS: CreateAddressInput = {
  destinatario: "",
  telefono: "",
  departamento: "",
  municipio: "",
  direccionLinea1: "",
  referencia: null
};

  // ==========================================
  // COTIZACION APLICADA AL CARRITO
  // ==========================================

  interface QuoteSnapshot {
    data: CouponQuote;
    cartSignature: string;
  }

  // ==========================================
  // INTENTO INMUTABLE DE CHECKOUT
  // ==========================================

  interface ReservationAttempt {
    idReserva: string;
    idCarrito: string;
    claveIdempotencia: string;
    idDireccion: number;
    totalEsperado: string;
    codigoCupon?: string;
    couponQuote: CouponQuote | null;
    cartSignature: string;
  }

  // ==========================================
  // VALIDAR UN INTENTO RECUPERADO
  // ==========================================

  function isReservationAttempt(
    value: unknown
  ): value is ReservationAttempt {
    if (
      value === null ||
      typeof value !== "object"
    ) {
      return false;
    }

    const item = value as Partial<ReservationAttempt>;

    const quote = item.couponQuote;

    const quoteValid =
      quote === null ||
      (
        typeof quote === "object" &&
        quote !== null &&
        typeof quote.idCarrito === "string" &&
        typeof quote.codigoCupon === "string" &&
        typeof quote.subtotal === "string" &&
        typeof quote.descuento === "string" &&
        typeof quote.total === "string"
      );

    return (
      typeof item.idReserva === "string" &&
      typeof item.idCarrito === "string" &&
      typeof item.claveIdempotencia === "string" &&
      /^[a-zA-Z0-9_-]{16,100}$/.test(
        item.claveIdempotencia
      ) &&
      Number.isSafeInteger(item.idDireccion) &&
      (item.idDireccion ?? 0) > 0 &&
      typeof item.totalEsperado === "string" &&
      /^(0|[1-9]\d{0,16})\.\d{2}$/.test(
        item.totalEsperado
      ) &&
      typeof item.cartSignature === "string" &&
      (
        item.codigoCupon === undefined ||
        (
          typeof item.codigoCupon === "string" &&
          /^[A-Z0-9_-]{3,50}$/.test(item.codigoCupon)
        )
      ) &&
      quoteValid
    );
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

  // ==========================================
  // ESTADO DEL CUPON
  // ==========================================

  const [couponCode, setCouponCode] =
    useState("");

  const [couponQuote, setCouponQuote] =
    useState<QuoteSnapshot | null>(null);

  const [quoting, setQuoting] =
    useState(false);

  // Evitar envios simultaneos.
  const quoteLock = useRef(false);
  const reserveLock = useRef(false);
  const confirmLock = useRef(false);

  // Identidad del contenido del carrito.
  // Se utiliza para detectar cotizaciones
  // realizadas sobre un carrito anterior.

  const cartSignature = cart
    ? JSON.stringify([
        cart.idCarrito,
        cart.subtotal,
        ...cart.items
          .map(item => (
            [
              item.idVariante,
              item.cantidad,
              item.precioUnitario,
              item.importeLinea
            ].join(":")
          ))
          .sort()
      ])
    : "";

  // Solo aceptamos una cotizacion que
  // corresponda al carrito y codigo actuales.

  const activeQuote =
    couponQuote !== null &&
    couponQuote.cartSignature === cartSignature &&
    couponQuote.data.codigoCupon ===
      couponCode.trim().toUpperCase()
      ? couponQuote.data
      : null;

  // Tras reservar, mostramos la cotizacion
  // congelada del intento original.

  const displayedQuote =
    reservation?.couponQuote ?? activeQuote;

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
  // COTIZAR CUPON SIN CONSUMIRLO
  // ========================================

  async function handleQuote(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();

    if (
      quoteLock.current ||
      reserveLock.current ||
      confirmLock.current ||
      reservation !== null ||
      !cart ||
      cartLoading ||
      cartBusy
    ) {
      return;
    }

    const code = couponCode.trim().toUpperCase();

    if (!/^[A-Z0-9_-]{3,50}$/.test(code)) {
      setError(
        "El codigo debe tener entre 3 y 50 caracteres: " +
        "letras, numeros, guion o guion bajo."
      );
      return;
    }

    quoteLock.current = true;
    setQuoting(true);
    setCouponQuote(null);
    setError(null);
    setMessage(null);

    try {
      const data = await quoteCheckout({
        idCarrito: cart.idCarrito,
        codigoCupon: code
      });

      if (
        data.idCarrito !== cart.idCarrito ||
        data.codigoCupon !== code ||
        data.subtotal !== cart.subtotal
      ) {
        throw new Error(
          "La cotizacion ya no coincide con este carrito. " +
          "Actualiza los productos y vuelve a intentar."
        );
      }

      setCouponCode(code);
      setCouponQuote({
        data,
        cartSignature
      });
      setMessage(
        "Cupon aplicado a la cotizacion. " +
        "El descuento se revalidara al confirmar."
      );
    } catch (cause) {
      setCouponQuote(null);
      setError(getErrorMessage(cause));
    } finally {
      quoteLock.current = false;
      setQuoting(false);
    }
  }

  // ========================================
  // QUITAR CUPON ANTES DE RESERVAR
  // ========================================

  function handleRemoveCoupon(): void {
    if (
      reservation !== null ||
      quoteLock.current ||
      reserveLock.current ||
      confirmLock.current
    ) {
      return;
    }

    setCouponCode("");
    setCouponQuote(null);
    setError(null);
    setMessage(null);
  }

  // ==========================================
  // RESERVAR INVENTARIO Y FIJAR EL INTENTO
  // ==========================================

  async function handleReserve(): Promise<void> {
    if (
      reserveLock.current ||
      confirmLock.current ||
      quoteLock.current ||
      !cart ||
      cart.items.length === 0 ||
      cartLoading ||
      cartBusy
    ) {
      return;
    }

    if (selectedAddressId === null) {
      setError("Selecciona una dirección de entrega.");
      return;
    }

    // Si se escribió un cupón, debe existir
    // una cotización vigente para este carrito.
    if (couponCode.trim() !== "" && !activeQuote) {
      setError(
        "Debes aplicar el cupón y obtener una " +
        "cotización válida antes de reservar."
      );
      return;
    }

    reserveLock.current = true;
    setReserving(true);
    setError(null);
    setMessage(null);

    try {
      const data = await reserveCheckout(
        cart.idCarrito
      );

      const storageKey =
        `shopcart:checkout:${data.idReserva}`;

      const stored = window.sessionStorage.getItem(
        storageKey
      );

      let attempt: ReservationAttempt;

      if (stored !== null) {
        // Recuperamos el mismo intento,
        // sin cambiar clave, dirección ni cupón.
        let recovered: unknown;

        try {
          recovered = JSON.parse(stored);
        } catch {
          throw new Error(
            "Existe un intento anterior que no puede " +
            "recuperarse de forma segura. " +
            "No se generará otra clave para esta reserva."
          );
        }

        if (
          !isReservationAttempt(recovered) ||
          recovered.idReserva !== data.idReserva ||
          recovered.idCarrito !== cart.idCarrito
        ) {
          throw new Error(
            "El intento guardado no coincide con la reserva."
          );
        }

        attempt = recovered;

        setMessage(
          "Se recuperó el intento original. " +
          "Se conservaron su cupón, dirección y " +
          "clave de idempotencia."
        );

      } else {
        attempt = {
          idReserva: data.idReserva,
          idCarrito: cart.idCarrito,
          claveIdempotencia: crypto.randomUUID(),
          idDireccion: selectedAddressId,
          totalEsperado: cart.subtotal,
          codigoCupon:
            activeQuote?.codigoCupon,
          couponQuote: activeQuote,
          cartSignature
        };

        // Guardar antes de permitir confirmar.
        window.sessionStorage.setItem(
          storageKey,
          JSON.stringify(attempt)
        );

        setMessage(
          "Inventario reservado. " +
          "Los datos de este intento quedaron fijados."
        );
      }

      setReservation(attempt);

      setSelectedAddressId(
        attempt.idDireccion
      );

      setCouponCode(
        attempt.codigoCupon ?? ""
      );

      setCouponQuote(
        attempt.couponQuote
          ? {
              data: attempt.couponQuote,
              cartSignature: attempt.cartSignature
            }
          : null
      );

    } catch (cause) {
      setError(getErrorMessage(cause));
    } finally {
      reserveLock.current = false;
      setReserving(false);
    }
  }

  // ==========================================
  // CONFIRMAR PEDIDO CON CUPON
  // ==========================================

  async function handleConfirm(): Promise<void> {
    if (
      !reservation ||
      confirmLock.current
    ) {
      return;
    }

    confirmLock.current = true;
    setConfirming(true);
    setError(null);
    setMessage(null);

    try {
      // Nunca recalculamos ni reemplazamos
      // los parametros de un intento existente.
      const result = await confirmCheckout({
        idReserva: reservation.idReserva,
        idDireccion: reservation.idDireccion,
        claveIdempotencia:
          reservation.claveIdempotencia,
        totalEsperado:
          reservation.totalEsperado,
        ...(reservation.codigoCupon
          ? {
              codigoCupon:
                reservation.codigoCupon
            }
          : {})
      });

      // Solo eliminamos el intento despues
      // de recibir confirmacion del servidor.
      window.sessionStorage.removeItem(
        `shopcart:checkout:${reservation.idReserva}`
      );

      navigate("/pedido-confirmado", {
        replace: true,
        state: {
          order: result
        }
      });

      void refresh();

    } catch (cause) {
      // Conservamos exactamente el mismo
      // intento para un reintento posterior.
      setError(getErrorMessage(cause));
    } finally {
      confirmLock.current = false;
      setConfirming(false);
    }
  }

  const isCartEmpty =
    !cart || cart.items.length === 0;

  const isBusy =
    savingAddress ||
    quoting ||
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
            <TicketPercent size={16} />
            2. Cupón
          </span>
          <span>
            <Clock3 size={16} />
            3. Reserva
          </span>
          <span>
            <CreditCard size={16} />
            4. Confirmación
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


            {/* ======================================
                CUPON PROMOCIONAL - PASO 75B.4
            ====================================== */}

            <section className="checkout-card">
              <div className="checkout-section-header">
                <div>
                  <span className="checkout-step-number">
                    02
                  </span>

                  <h2>Cupón promocional</h2>
                </div>

                <TicketPercent size={22} />
              </div>

              <p className="checkout-description">
                ¿Tienes un código de descuento?
                Introdúcelo para consultar el ahorro
                antes de confirmar tu compra.
              </p>

              <form
                className="checkout-coupon-form"
                onSubmit={event => {
                  void handleQuote(event);
                }}
              >
                <label htmlFor="checkout-coupon-code">
                  Código promocional
                </label>

                <div className="checkout-coupon-controls">
                  <input
                    id="checkout-coupon-code"
                    type="text"
                    placeholder="Ej. DESCUENTO10"
                    maxLength={50}
                    autoComplete="off"
                    value={couponCode}
                    disabled={reservation !== null || isBusy}
                    onChange={event => {
                      setCouponCode(
                        event.target.value.toUpperCase()
                      );
                      setCouponQuote(null);
                      setError(null);
                      setMessage(null);
                    }}
                  />

                  <button
                    type="submit"
                    className="btn btn-primary"
                    disabled={
                      reservation !== null ||
                      isBusy ||
                      couponCode.trim() === ""
                    }
                  >
                    {quoting ? "Validando..." : "Aplicar"}
                  </button>
                </div>
              </form>

              {!reservation && couponCode.trim() !== "" && (
                <button
                  type="button"
                  className="checkout-coupon-remove"
                  disabled={isBusy}
                  onClick={handleRemoveCoupon}
                >
                  Quitar código
                </button>
              )}

              {displayedQuote && (
                <div
                  className="checkout-coupon-success"
                  role="status"
                >
                  <CheckCircle2 size={20} />

                  <div>
                    <strong>
                      Cupón {displayedQuote.codigoCupon}
                    </strong>

                    <p>
                      Ahorro estimado:{" "}
                      {formatGTQ(displayedQuote.descuento)}
                    </p>

                    <small>
                      Total cotizado:{" "}
                      {formatGTQ(displayedQuote.total)}
                    </small>
                  </div>
                </div>
              )}

              {reservation && (
                <p className="checkout-coupon-note">
                  El código promocional está bloqueado
                  para esta reserva. La confirmación
                  volverá a validar su vigencia y
                  disponibilidad.
                </p>
              )}

              {!reservation &&
                couponCode.trim() !== "" &&
                !activeQuote &&
                !quoting && (
                  <p className="checkout-coupon-note">
                    Debes aplicar y validar este código
                    antes de reservar el inventario.
                  </p>
                )}
            </section>


            {/* RESERVA */}

            <section className="checkout-card">
              <div className="checkout-section-header">
                <div>
                  <span className="checkout-step-number">
                    03
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
                    selectedAddressId === null ||
                    (
                      couponCode.trim() !== "" &&
                      !activeQuote
                    )
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
                    04
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
                {formatGTQ(
                  reservation?.totalEsperado ?? cart.subtotal
                )}
              </strong>
            </div>

            {displayedQuote && (
              <div className="checkout-summary-row checkout-discount">
                <span>
                  Descuento ({displayedQuote.codigoCupon})
                </span>
                <strong>
                  -{formatGTQ(displayedQuote.descuento)}
                </strong>
              </div>
            )}

            {!displayedQuote && (
              <div className="checkout-summary-row">
                <span>Descuento</span>
                <strong>{formatGTQ(cart.descuento)}</strong>
              </div>
            )}

            <div className="checkout-summary-total">
              <span>Total estimado</span>
              <strong>
                {formatGTQ(displayedQuote?.total ?? cart.total)}
              </strong>
            </div>

            <p className="checkout-summary-note">
              Montos en quetzales, IVA incluido.
              La confirmación volverá a verificar
              el total en SQL Server.
            </p>

            <p className="checkout-summary-note">
              Los descuentos son calculados por SQL Server.
              La cotización es informativa y puede cambiar
              antes de confirmar el pedido.
            </p>
          </aside>

        </div>
      </div>
    </main>
  );
}
