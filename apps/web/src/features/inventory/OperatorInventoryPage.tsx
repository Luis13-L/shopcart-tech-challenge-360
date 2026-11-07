import {
  useEffect,
  useRef,
  useState,
  type FormEvent
} from "react";

import {
  ArrowLeft,
  Boxes,
  ClipboardList,
  RefreshCw
} from "lucide-react";

import { Link } from "react-router";

import {
  confirmAction,
  showError,
  showSuccess
} from "../../lib/alerts";

import {
  formatOrderDate
} from "../orders/orders.api";

import {
  createInventoryMovement,
  getInventoryKardex,
  getInventoryStock,
  InventoryApiError,
  type InventoryKardex,
  type InventoryStock,
  type ManualMovementType
} from "./inventory.api";

const movementLabels: Record<
  ManualMovementType,
  string
> = {
  ENTRADA: "Entrada de inventario",
  AJUSTE_POSITIVO: "Ajuste positivo",
  AJUSTE_NEGATIVO: "Ajuste negativo"
};

function getErrorMessage(error: unknown): string {
  return error instanceof Error
    ? error.message
    : "Ocurrió un error inesperado";
}

export function OperatorInventoryPage() {
  const [variantInput, setVariantInput] =
    useState("");

  const [variantId, setVariantId] =
    useState<number | null>(null);

  const [stock, setStock] =
    useState<InventoryStock | null>(null);

  const [kardex, setKardex] =
    useState<InventoryKardex | null>(null);

  const [page, setPage] = useState(1);
  const [reload, setReload] = useState(0);

  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const savingRef = useRef(false);

  const [error, setError] =
    useState<string | null>(null);

  const [movementType, setMovementType] =
    useState<ManualMovementType>("ENTRADA");

  const [quantity, setQuantity] = useState("");
  const [reason, setReason] = useState("");

  // ========================================
  // CONSULTAR EXISTENCIAS Y KARDEX
  // ========================================

  useEffect(() => {
    if (variantId === null) return;

    const controller = new AbortController();

    setLoading(true);
    setError(null);
    setStock(null);
    setKardex(null);

    Promise.all([
      getInventoryStock(
        variantId,
        controller.signal
      ),
      getInventoryKardex(
        variantId,
        page,
        controller.signal
      )
    ])
      .then(([stockData, kardexData]) => {
        if (!controller.signal.aborted) {
          setStock(stockData);
          setKardex(kardexData);
        }
      })
      .catch((cause: unknown) => {
        if (!controller.signal.aborted) {
          setError(getErrorMessage(cause));
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [variantId, page, reload]);

  // ========================================
  // BUSCAR VARIANTE POR ID
  // ========================================

  function handleSearch(
    event: FormEvent<HTMLFormElement>
  ): void {
    event.preventDefault();

    if (savingRef.current) return;

    const id = Number(variantInput);

    if (
      !Number.isSafeInteger(id) ||
      id < 1 ||
      id > 2147483647
    ) {
      setError(
        "Ingresa un ID de variante válido."
      );
      return;
    }

    setError(null);
    setPage(1);
    setVariantId(id);
    setReload(current => current + 1);
  }

  // ========================================
  // REGISTRAR MOVIMIENTO
  // ========================================

  async function handleMovement(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();

    if (
      savingRef.current ||
      stock === null
    ) {
      return;
    }

    const parsedQuantity = Number(quantity);
    const trimmedReason = reason.trim();

    if (
      !Number.isSafeInteger(parsedQuantity) ||
      parsedQuantity < 1 ||
      parsedQuantity > 2147483647
    ) {
      await showError(
        "Cantidad inválida",
        "Ingresa un entero positivo válido."
      );
      return;
    }

    if (
      trimmedReason.length < 3 ||
      trimmedReason.length > 300
    ) {
      await showError(
        "Motivo inválido",
        "Ingresa un motivo de 3 a 300 caracteres."
      );
      return;
    }

    if (
      movementType === "AJUSTE_NEGATIVO" &&
      parsedQuantity > stock.cantidadDisponible
    ) {
      await showError(
        "Existencias insuficientes",
        "No puedes descontar más unidades " +
        "de las disponibles, ya que algunas " +
        "podrían estar reservadas."
      );
      return;
    }

    savingRef.current = true;
    setSaving(true);

    try {
      const confirmed = await confirmAction({
        title: "¿Registrar movimiento?",
        text:
          `Variante: ${stock.sku}. ` +
          `Operación: ${movementLabels[movementType]}. ` +
          `Cantidad: ${parsedQuantity}. ` +
          "Esta operación modificará el inventario.",
        confirmText: "Sí, registrar",
        danger:
          movementType === "AJUSTE_NEGATIVO"
      });

      if (!confirmed) return;

      const result = await createInventoryMovement({
        idVariante: stock.idVariante,
        tipoMovimiento: movementType,
        cantidad: parsedQuantity,
        motivo: trimmedReason
      });

      setQuantity("");
      setReason("");
      setPage(1);
      setReload(current => current + 1);

      await showSuccess(
        "Movimiento registrado",
        `Movimiento #${result.idMovimientoInventario}. ` +
        `Saldo anterior: ${result.saldoAnterior}. ` +
        `Nuevo saldo: ${result.saldoPosterior}.`
      );

    } catch (cause) {
      const rejectedByApi =
        cause instanceof InventoryApiError &&
        cause.status >= 400 &&
        cause.status < 500;

      const message = rejectedByApi
        ? getErrorMessage(cause)
        : getErrorMessage(cause) +
          ". No sabemos si la operación llegó " +
          "a registrarse. Revisa el kardex " +
          "antes de intentar otra vez.";

      setReload(current => current + 1);

      await showError(
        "No se pudo confirmar el movimiento",
        message
      );

    } finally {
      savingRef.current = false;
      setSaving(false);
    }
  }

  const records = kardex?.items ?? [];
  const pagination = kardex?.pagination;

  return (
    <main className="operator-page">
      <div className="operator-container">

        <Link
          to="/operacion"
          className="orders-back"
        >
          <ArrowLeft size={18} />
          Volver al panel
        </Link>

        <header className="operator-heading">
          <div>
            <span className="eyebrow">
              SHOPCART / OPERACIONES
            </span>
            <h1>Inventario y Kardex</h1>
            <p>
              Control de existencias y trazabilidad
              de movimientos por variante.
            </p>
          </div>
          <Boxes size={38} />
        </header>

        {/* BUSCAR VARIANTE */}

        <section className="orders-panel order-section">
          <h2>Consultar variante</h2>

          <p className="order-action-help">
            Ingresa el ID de una variante.
            Puedes obtenerlo del catálogo de
            productos de ShopCart.
          </p>

          <form
            className="inventory-search"
            onSubmit={handleSearch}
          >
            <label htmlFor="inventory-variant">
              ID de variante
            </label>

            <input
              id="inventory-variant"
              type="number"
              min={1}
              max={2147483647}
              step={1}
              required
              placeholder="Ejemplo: 4"
              value={variantInput}
              disabled={saving}
              onChange={event => {
                setVariantInput(event.target.value);
              }}
            />

            <button
              type="submit"
              className="operator-primary"
              disabled={saving || loading}
            >
              <RefreshCw size={17} />
              Consultar
            </button>
          </form>
        </section>

        {variantId === null ? (
          <section className="operator-empty">
            <ClipboardList size={40} />
            <h2>Selecciona una variante</h2>
            <p>
              Ingresa su ID para visualizar las
              existencias y el historial.
            </p>

            {error && (
              <p role="alert">{error}</p>
            )}
          </section>

        ) : loading ? (
          <section
            className="operator-empty"
            role="status"
          >
            <span className="auth-spinner" />
            <p>Consultando inventario...</p>
          </section>

        ) : error ? (
          <section
            className="operator-empty"
            role="alert"
          >
            <h2>No se pudo consultar</h2>
            <p>{error}</p>

            <button
              type="button"
              className="operator-primary"
              onClick={() => {
                setReload(value => value + 1);
              }}
            >
              Reintentar consulta
            </button>
          </section>

        ) : stock && kardex ? (
          <>
            {/* EXISTENCIAS */}

            <section className="inventory-stats">
              <article className="inventory-stat">
                <small>Existencia física</small>
                <strong>
                  {stock.cantidadFisica}
                </strong>
              </article>

              <article className="inventory-stat">
                <small>Unidades reservadas</small>
                <strong>
                  {stock.cantidadReservada}
                </strong>
              </article>

              <article className="inventory-stat">
                <small>Disponible</small>
                <strong>
                  {stock.cantidadDisponible}
                </strong>
              </article>
            </section>

            <p className="inventory-sku">
              Variante #{stock.idVariante}
              {" · "}
              SKU: <strong>{stock.sku}</strong>
              {" · "}
              Actualizado:
              {" "}
              {formatOrderDate(
                stock.fechaActualizacion
              )}
            </p>

            <div className="inventory-layout">

              {/* FORMULARIO DE MOVIMIENTO */}

              <section className="orders-panel order-section">
                <h2>Registrar movimiento</h2>

                <p className="order-action-help">
                  Los ajustes requieren un motivo.
                  Las ventas y devoluciones se
                  registran automáticamente
                  desde sus respectivos procesos.
                </p>

                <form
                  className="inventory-form"
                  onSubmit={event => {
                    void handleMovement(event);
                  }}
                >
                  <label htmlFor="movement-type">
                    Tipo de movimiento
                  </label>

                  <select
                    id="movement-type"
                    value={movementType}
                    disabled={saving}
                    onChange={event => {
                      const selected =
                        event.currentTarget.value;

                      const validTypes:
                        ManualMovementType[] = [
                          "ENTRADA",
                          "AJUSTE_POSITIVO",
                          "AJUSTE_NEGATIVO"
                        ];

                      const matched =
                        validTypes.find(
                          type => type === selected
                        );

                      if (matched) {
                        setMovementType(matched);
                      }
                    }}
                  >
                    <option value="ENTRADA">
                      Entrada
                    </option>
                    <option value="AJUSTE_POSITIVO">
                      Ajuste positivo
                    </option>
                    <option value="AJUSTE_NEGATIVO">
                      Ajuste negativo
                    </option>
                  </select>

                  <label htmlFor="movement-quantity">
                    Cantidad
                  </label>

                  <input
                    id="movement-quantity"
                    type="number"
                    min={1}
                    max={2147483647}
                    step={1}
                    required
                    value={quantity}
                    disabled={saving}
                    onChange={event => {
                      setQuantity(event.target.value);
                    }}
                  />

                  <label htmlFor="movement-reason">
                    Motivo
                  </label>

                  <textarea
                    id="movement-reason"
                    required
                    minLength={3}
                    maxLength={300}
                    rows={4}
                    placeholder="Describe el motivo..."
                    value={reason}
                    disabled={saving}
                    onChange={event => {
                      setReason(event.target.value);
                    }}
                  />

                  <button
                    type="submit"
                    className="operator-primary"
                    disabled={saving || loading}
                  >
                    {saving
                      ? "Procesando..."
                      : "Registrar movimiento"}
                  </button>
                </form>
              </section>

              {/* KARDEX */}

              <section className="orders-panel order-section">
                <div className="inventory-section-header">
                  <div>
                    <h2>Kardex</h2>
                    <p className="order-action-help">
                      Historial de movimientos
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

                {records.length === 0 ? (
                  <p className="order-action-help">
                    No hay movimientos para mostrar.
                  </p>
                ) : (
                  <div className="inventory-table-scroll">
                    <table className="inventory-table">
                      <thead>
                        <tr>
                          <th>Fecha</th>
                          <th>Movimiento</th>
                          <th>Cantidad</th>
                          <th>Saldo</th>
                          <th>Responsable</th>
                          <th>Motivo</th>
                        </tr>
                      </thead>

                      <tbody>
                        {records.map(item => (
                          <tr
                            key={
                              item.idMovimientoInventario
                            }
                          >
                            <td>
                              {formatOrderDate(
                                item.fechaMovimiento
                              )}
                            </td>

                            <td>
                              {item.tipoMovimiento}
                            </td>

                            <td>
                              <strong>
                                {item.cantidadFirmada > 0
                                  ? "+"
                                  : ""}
                                {item.cantidadFirmada}
                              </strong>
                            </td>

                            <td>
                              {item.saldoAnterior}
                              {" → "}
                              {item.saldoPosterior}
                            </td>

                            <td>
                              {item.idUsuario
                                ? `#${item.idUsuario}`
                                : "Sistema"}
                            </td>

                            <td>
                              {item.motivo || "—"}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}

                {pagination &&
                  pagination.totalPaginas > 1 && (
                    <nav
                      className="orders-pagination"
                      aria-label="Páginas del kardex"
                    >
                      <button
                        type="button"
                        disabled={
                          page <= 1 || saving
                        }
                        onClick={() => {
                          setPage(value => value - 1);
                        }}
                      >
                        Anterior
                      </button>

                      <span>
                        Página {pagination.pagina}
                        {" de "}
                        {pagination.totalPaginas}
                      </span>

                      <button
                        type="button"
                        disabled={
                          page >=
                          pagination.totalPaginas ||
                          saving
                        }
                        onClick={() => {
                          setPage(value => value + 1);
                        }}
                      >
                        Siguiente
                      </button>
                    </nav>
                  )}
              </section>
            </div>
          </>
        ) : null}

      </div>
    </main>
  );
}
