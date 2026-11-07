import {
  useEffect,
  useRef,
  useState,
  type FormEvent
} from "react";

import {
  RotateCcw,
  ShieldCheck
} from "lucide-react";

import { useAuth } from "../../auth/AuthProvider";

import type {
  OrderDetail
} from "./orders.api";

import {
  requestOrderReturn,
  ReturnApiError,
  type ReturnOrderInput,
  type ReturnOrderResult
} from "./orders.returns.api";

interface Props {
  order: OrderDetail;
  onCompleted: (result: ReturnOrderResult) => void;
}

function getMessage(error: unknown): string {
  return error instanceof Error
    ? error.message
    : "No se pudo procesar la devolución";
}

export function ReturnOrderPanel({
  order,
  onCompleted
}: Props) {

  const { session } = useAuth();

  const userId = session?.user.id;

  const storageKey =
    `shopcart:return:v1:${userId}:${order.idPedido}`;

  const availableItems = order.productos.filter(
    item => item.cantidad > item.cantidadDevuelta
  );

  const [detailId, setDetailId] =
    useState<string>("");

  const [quantity, setQuantity] = useState("1");
  const [reason, setReason] = useState("");

  const [pending, setPending] =
    useState<ReturnOrderInput | null>(null);

  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);

  const [error, setError] =
    useState<string | null>(null);

  // ========================================
  // RECUPERAR INTENTO PENDIENTE
  // ========================================

  useEffect(() => {
    setError(null);
    setPending(null);

    try {
      const raw = sessionStorage.getItem(storageKey);

      if (!raw) return;

      const value: unknown = JSON.parse(raw);

      if (
        typeof value !== "object" ||
        value === null ||
        !("idDetallePedido" in value) ||
        typeof value.idDetallePedido !== "string" ||
        !("cantidad" in value) ||
        typeof value.cantidad !== "number" ||
        !("motivo" in value) ||
        typeof value.motivo !== "string" ||
        !("claveIdempotencia" in value) ||
        typeof value.claveIdempotencia !== "string"
      ) {
        return;
      }

      const attempt = value as ReturnOrderInput;

      setPending(attempt);
      setDetailId(attempt.idDetallePedido);
      setQuantity(String(attempt.cantidad));
      setReason(attempt.motivo);

    } catch {
      setError(
        "No se pudo recuperar el intento anterior. " +
        "Verifica el estado del pedido antes de intentar otra devolución."
      );
    }
  }, [storageKey]);

  // ========================================
  // PRODUCTO SELECCIONADO
  // ========================================

    const selectedItem = pending
    ? order.productos.find(
        item =>
            item.idDetallePedido ===
            pending.idDetallePedido
        )
    : availableItems.find(
        item => item.idDetallePedido === detailId
        ) ?? availableItems[0];

    const remaining = selectedItem
    ? selectedItem.cantidad -
        selectedItem.cantidadDevuelta
    : 0;
  // ========================================
  // PROCESAR DEVOLUCION
  // ========================================

  async function handleSubmit(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();

    if (busyRef.current || !userId) return;

    setError(null);

    // Reintentos: reutilizar la solicitud
    // original sin cambiar ni un campo.
    let attempt = pending;

    if (!attempt) {
      if (!selectedItem) return;

      const parsedQuantity = Number(quantity);
      const trimmedReason = reason.trim();

      if (
        !Number.isSafeInteger(parsedQuantity) ||
        parsedQuantity < 1 ||
        parsedQuantity > remaining
      ) {
        setError(
          `La cantidad debe estar entre 1 y ${remaining}.`
        );
        return;
      }

      if (
        trimmedReason.length < 1 ||
        trimmedReason.length > 300
      ) {
        setError(
          "El motivo debe tener entre 1 y 300 caracteres."
        );
        return;
      }

      attempt = {
        idDetallePedido: selectedItem.idDetallePedido,
        cantidad: parsedQuantity,
        motivo: trimmedReason,
        claveIdempotencia: crypto.randomUUID()
      };

      // Guardar ANTES de enviar al servidor.
      // Si falla el almacenamiento, no enviamos.
      try {
        sessionStorage.setItem(
          storageKey,
          JSON.stringify(attempt)
        );
      } catch {
        setError(
          "No se pudo conservar la clave de seguridad del intento."
        );
        return;
      }

      setPending(attempt);
    }

    busyRef.current = true;
    setBusy(true);

    try {
      const result = await requestOrderReturn(
        order.idPedido,
        attempt
      );

      // Solo una respuesta exitosa confirma
      // que ya podemos cerrar el intento.
      try {
        sessionStorage.removeItem(storageKey);
      } catch {
        // El servidor ya confirmó la operación.
      }

      setPending(null);

      onCompleted(result);

    } catch (cause) {
      // Ante errores confirmados 4xx, la
      // operación fue rechazada por la API.
      // Es válido corregir los datos y crear
      // posteriormente una solicitud nueva.
      if (
        cause instanceof ReturnApiError &&
        cause.status >= 400 &&
        cause.status < 500 &&
        cause.status !== 429
      ) {
        try {
          sessionStorage.removeItem(storageKey);
        } catch {
          // No ocultar el error de la API.
        }

        setPending(null);
      }

      setError(getMessage(cause));

    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  if (availableItems.length === 0) {
    return null;
  }

  return (
    <section className="orders-panel order-section">

      <div className="order-section-title">
        <RotateCcw size={22} />
        <h2>Solicitar devolución</h2>
      </div>

      <p className="order-action-help">
        Selecciona el producto y la cantidad.
        Las unidades ya devueltas no pueden
        solicitarse nuevamente.
      </p>

      {pending && (
        <div
          className="return-pending"
          role="status"
        >
          <ShieldCheck size={20} />

          <div>
            <strong>
              Intento anterior pendiente de verificar
            </strong>

            <p>
              Para evitar duplicidades, se
              reintentará la misma solicitud
              con su clave original.
            </p>
          </div>
        </div>
      )}

      {error && (
        <div
          className="cart-feedback error"
          role="alert"
        >
          {error}
        </div>
      )}

      <form
        className="return-form"
        onSubmit={event => {
          void handleSubmit(event);
        }}
      >

        <label htmlFor="return-item">
          Producto
        </label>

        
        <select
        id="return-item"
        required
        value={selectedItem?.idDetallePedido ?? ""}
        disabled={busy || pending !== null}
        onChange={event => {
            setDetailId(event.target.value);
            setQuantity("1");
        }}
        >
        {/* Recuperar producto de un intento pendiente */}
        {pending &&
            selectedItem &&
            !availableItems.some(
            item =>
                item.idDetallePedido ===
                selectedItem.idDetallePedido
            ) && (
            <option value={selectedItem.idDetallePedido}>
                {selectedItem.nombreProducto}
                {" "}— intento pendiente
            </option>
            )}

        {/* Productos disponibles para devolver */}
        {availableItems.map(item => (
            <option
            key={item.idDetallePedido}
            value={item.idDetallePedido}
            >
            {item.nombreProducto}
            </option>
        ))}
        </select>


        <p className="return-remaining">
          Unidades disponibles para devolver:
          {" "}
          <strong>{remaining}</strong>
        </p>

        <label htmlFor="return-quantity">
          Cantidad a devolver
        </label>

        <input
          id="return-quantity"
          type="number"
          min={1}
          max={remaining}
          step={1}
          required
          value={quantity}
          disabled={busy || pending !== null}
          onChange={event => {
            setQuantity(event.target.value);
          }}
        />

        <label htmlFor="return-reason">
          Motivo de la devolución
        </label>

        <textarea
          id="return-reason"
          rows={4}
          maxLength={300}
          required
          disabled={busy || pending !== null}
          placeholder="Describe el motivo de tu devolución..."
          value={reason}
          onChange={event => {
            setReason(event.target.value);
          }}
        />

        <small className="return-help">
          El importe del reembolso será
          determinado por SQL Server,
          considerando los descuentos del pedido.
        </small>

        <button
          type="submit"
          className="return-submit"
          disabled={busy || !selectedItem}
        >
          <RotateCcw size={17} />

          {busy
            ? "Procesando devolución..."
            : pending
              ? "Reintentar misma devolución"
              : "Confirmar devolución"}
        </button>

      </form>
    </section>
  );
}
