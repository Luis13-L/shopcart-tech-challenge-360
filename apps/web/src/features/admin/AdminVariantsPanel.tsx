import {
  useEffect,
  useRef,
  useState,
  type FormEvent
} from "react";
import { Plus, RefreshCw, Tag, X } from "lucide-react";
import { formatGTQ } from "../../lib/catalog";
import { confirmAction, showError, showSuccess } from "../../lib/alerts";
import type { AdminProduct } from "./admin.products.list.api";
import {
  getAdminVariants,
  createAdminVariant,
  changeAdminVariantStatus,
  type AdminVariant,
  type AdminVariantsResult,
  type VariantAttribute
} from "./admin.variants.api";
import "./admin-variants.css";

interface Props {
  product: AdminProduct;
  revision: number;
  onChanged: () => void;
  onEditPrice: (variant: AdminVariant) => void;
  onClose: () => void;
}

const emptyAttribute = (): VariantAttribute => ({
  nombre: "",
  valor: ""
});

const pricePattern = /^(?:0|[1-9]\d{0,8})(?:\.\d{1,2})?$/;
const skuPattern = /^[A-Z0-9._-]{3,64}$/;

function errorText(error: unknown): string {
  return error instanceof Error
    ? error.message
    : "Ocurrió un error inesperado";
}

export function AdminVariantsPanel({
  product,
  revision,
  onChanged,
  onEditPrice,
  onClose
}: Props) {
  const [page, setPage] = useState(1);
  const [refresh, setRefresh] = useState(0);
  const [result, setResult] =
    useState<AdminVariantsResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);
  const [showForm, setShowForm] = useState(false);
  const [sku, setSku] = useState("");
  const [price, setPrice] = useState("");
  const [attributes, setAttributes] =
    useState<VariantAttribute[]>([emptyAttribute()]);

  const canManage = product.activo && product.categoriaActiva;
  const items = result?.items ?? [];
  const pagination = result?.pagination;

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError(null);
    setResult(null);

    getAdminVariants(product.idProducto, page, controller.signal)
      .then(data => {
        if (controller.signal.aborted) return;
        if (page > 1 && page > data.pagination.totalPaginas) {
          setPage(Math.max(1, data.pagination.totalPaginas));
          return;
        }
        setResult(data);
      })
      .catch((cause: unknown) => {
        if (!controller.signal.aborted) {
          setError(errorText(cause));
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });

    return () => controller.abort();
  }, [product.idProducto, page, refresh, revision]);

  function reload(): void {
    setRefresh(value => value + 1);
    onChanged();
  }

  function resetForm(): void {
    setSku("");
    setPrice("");
    setAttributes([emptyAttribute()]);
    setShowForm(false);
  }

  function updateAttribute(
    index: number,
    key: keyof VariantAttribute,
    value: string
  ): void {
    setAttributes(current => current.map((attribute, i) =>
      i === index ? { ...attribute, [key]: value } : attribute
    ));
  }

  async function handleCreate(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();
    if (busyRef.current || !canManage) return;

    const normalizedSku = sku.trim().toUpperCase();
    const normalizedPrice = price.trim();
    const normalizedAttributes = attributes.map(attribute => ({
      nombre: attribute.nombre.trim(),
      valor: attribute.valor.trim()
    }));
    const names = normalizedAttributes.map(item =>
      item.nombre.toLocaleLowerCase("es-GT")
    );

    const validAttributes = normalizedAttributes.length >= 1 &&
      normalizedAttributes.length <= 8 &&
      normalizedAttributes.every(item =>
        item.nombre.length >= 1 &&
        item.nombre.length <= 60 &&
        item.valor.length >= 1 &&
        item.valor.length <= 100
      ) && new Set(names).size === names.length;

    if (
      !skuPattern.test(normalizedSku) ||
      !pricePattern.test(normalizedPrice) ||
      Number(normalizedPrice) <= 0 ||
      !validAttributes
    ) {
      await showError(
        "Datos inválidos",
        "Revisa el SKU, el precio y los atributos. Los nombres de atributos no pueden repetirse."
      );
      return;
    }

    busyRef.current = true;
    setBusy(true);
    try {
      const confirmed = await confirmAction({
        title: "¿Crear variante?",
        text: `${normalizedSku} — ${formatGTQ(normalizedPrice)}. La existencia inicial será cero.`,
        confirmText: "Crear variante"
      });
      if (!confirmed) return;

      await createAdminVariant({
        idProducto: product.idProducto,
        sku: normalizedSku,
        precioActual: normalizedPrice,
        atributos: normalizedAttributes
      });
      resetForm();
      setPage(1);
      reload();
      await showSuccess(
        "Variante creada",
        "La variante fue registrada con existencia inicial cero."
      );
    } catch (cause) {
      reload();
      await showError(
        "No se pudo confirmar la creación",
        errorText(cause) + ". Consulta el listado antes de reintentar."
      );
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  async function handleStatus(variant: AdminVariant): Promise<void> {
    if (busyRef.current || !canManage) return;
    const nextStatus = !variant.activa;
    busyRef.current = true;
    setBusy(true);

    try {
      const confirmed = await confirmAction({
        title: nextStatus ? "¿Activar variante?" : "¿Desactivar variante?",
        text: `${variant.sku} — ${nextStatus ? "volverá a estar disponible" : "dejará de estar disponible para nuevas compras"}.`,
        confirmText: nextStatus ? "Activar" : "Desactivar",
        danger: !nextStatus
      });
      if (!confirmed) return;

      const response = await changeAdminVariantStatus(
        variant.idVariante,
        nextStatus
      );
      reload();
      await showSuccess(
        "Estado actualizado",
        response.actualizado
          ? "El estado de la variante se actualizó correctamente."
          : "La variante ya tenía el estado solicitado."
      );
    } catch (cause) {
      reload();
      await showError(
        "No se pudo confirmar el cambio",
        errorText(cause) + ". Consulta el listado antes de reintentar."
      );
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  return (
    <section className="admin-product-card admin-variants-panel">
      <div className="admin-variants-heading">
        <div>
          <h2>Variantes de {product.nombreProducto}</h2>
          <p className="admin-product-note">
            Producto #{product.idProducto} · SKU, atributos, precio y existencias por variante.
          </p>
        </div>
        <div className="admin-variants-toolbar">
          <button
            type="button"
            className="operator-refresh"
            disabled={busy || loading}
            onClick={() => setRefresh(value => value + 1)}
          >
            <RefreshCw size={16} /> Actualizar
          </button>
          <button
            type="button"
            className="operator-refresh"
            disabled={busy}
            onClick={onClose}
          >
            <X size={16} /> Cerrar
          </button>
        </div>
      </div>

      {!canManage && (
        <p className="admin-variants-warning" role="note">
          Este producto o su categoría está inactivo. Puedes consultar sus variantes,
          pero no crear ni cambiar su estado hasta reactivarlos.
        </p>
      )}

      {canManage && (
        <div className="admin-variants-create-toggle">
          <button
            type="button"
            className="operator-primary"
            disabled={busy}
            onClick={() => setShowForm(value => !value)}
          >
            <Plus size={16} /> {showForm ? "Ocultar formulario" : "Agregar variante"}
          </button>
        </div>
      )}

      {canManage && showForm && (
        <form className="admin-product-form admin-variants-form" onSubmit={event => {
          void handleCreate(event);
        }}>
          <label>
            SKU único
            <input
              required
              maxLength={64}
              minLength={3}
              placeholder="BOT-500-ROJO-003"
              value={sku}
              disabled={busy}
              onChange={event => setSku(event.target.value)}
            />
          </label>
          <label>
            Precio (Q)
            <input
              required
              inputMode="decimal"
              placeholder="175.00"
              value={price}
              disabled={busy}
              onChange={event => setPrice(event.target.value)}
            />
          </label>

          <div className="admin-product-wide">
            <h3>Atributos (1 a 8)</h3>
            {attributes.map((attribute, index) => (
              <div className="admin-variants-attribute-row" key={index}>
                <label>
                  Nombre
                  <input
                    required
                    maxLength={60}
                    placeholder="Color"
                    disabled={busy}
                    value={attribute.nombre}
                    onChange={event => updateAttribute(index, "nombre", event.target.value)}
                  />
                </label>
                <label>
                  Valor
                  <input
                    required
                    maxLength={100}
                    placeholder="Azul"
                    disabled={busy}
                    value={attribute.valor}
                    onChange={event => updateAttribute(index, "valor", event.target.value)}
                  />
                </label>
                <button
                  type="button"
                  className="operator-refresh"
                  disabled={busy || attributes.length === 1}
                  onClick={() => setAttributes(current => current.filter((_, i) => i !== index))}
                >
                  Quitar
                </button>
              </div>
            ))}
            <button
              type="button"
              className="operator-refresh"
              disabled={busy || attributes.length >= 8}
              onClick={() => setAttributes(current => [...current, emptyAttribute()])}
            >
              <Plus size={14} /> Agregar atributo
            </button>
          </div>

          <div className="admin-product-wide admin-variants-form-actions">
            <button type="submit" className="operator-primary" disabled={busy}>
              Crear variante
            </button>
            <button type="button" className="operator-refresh" disabled={busy} onClick={resetForm}>
              Cancelar
            </button>
          </div>
        </form>
      )}

      {loading ? (
        <p role="status">Cargando variantes...</p>
      ) : error ? (
        <p role="alert">{error}</p>
      ) : items.length === 0 ? (
        <p className="admin-product-note">Este producto todavía no tiene variantes.</p>
      ) : (
        <div className="admin-product-table-scroll">
          <table className="admin-product-table">
            <thead>
              <tr>
                <th scope="col">SKU / Variante</th>
                <th scope="col">Atributos</th>
                <th scope="col">Precio</th>
                <th scope="col">Existencia</th>
                <th scope="col">Estado</th>
                <th scope="col">Acciones</th>
              </tr>
            </thead>
            <tbody>
              {items.map(variant => (
                <tr key={variant.idVariante}>
                  <td>
                    <strong>{variant.sku}</strong>
                    <small>Variante #{variant.idVariante}</small>
                  </td>
                  <td>
                    {variant.atributos.length === 0
                      ? <span className="admin-variants-muted">Sin atributos</span>
                      : variant.atributos.map(attribute => (
                        <span className="admin-variants-attribute" key={attribute.nombre}>
                          {attribute.nombre}: {attribute.valor}
                        </span>
                      ))}
                  </td>
                  <td>{formatGTQ(variant.precioActual)}</td>
                  <td>{variant.cantidadFisica}</td>
                  <td>
                    <span className={variant.activa
                      ? "admin-product-status active"
                      : "admin-product-status inactive"}
                    >
                      {variant.activa ? "Activa" : "Inactiva"}
                    </span>
                  </td>
                  <td>
                    <div className="admin-product-actions">
                      <button
                        type="button"
                        disabled={busy || !canManage || !variant.activa}
                        onClick={() => onEditPrice(variant)}
                      >
                        <Tag size={15} /> Precio
                      </button>
                      <button
                        type="button"
                        disabled={busy || !canManage}
                        onClick={() => void handleStatus(variant)}
                      >
                        {variant.activa ? "Desactivar" : "Activar"}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {pagination && pagination.totalPaginas > 1 && (
        <nav className="orders-pagination" aria-label="Paginación de variantes">
          <button type="button" disabled={busy || loading || page <= 1} onClick={() => setPage(current => current - 1)}>
            Anterior
          </button>
          <span>Página {page} de {pagination.totalPaginas}</span>
          <button type="button" disabled={busy || loading || page >= pagination.totalPaginas} onClick={() => setPage(current => current + 1)}>
            Siguiente
          </button>
        </nav>
      )}
      {!loading && !error && pagination && (
        <p className="admin-product-note">
          {pagination.totalRegistros} variante(s). La existencia se modifica desde Inventario;
          este formulario no altera stock ni Kardex.
        </p>
      )}
    </section>
  );
}
