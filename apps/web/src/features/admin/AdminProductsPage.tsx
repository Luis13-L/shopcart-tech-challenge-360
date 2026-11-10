import {
  useEffect,
  useRef,
  useState,
  type FormEvent
} from "react";
import {
  ArrowLeft,
  Package,
  Pencil,
  RefreshCw,
  Tag,
  Power,
  Layers
} from "lucide-react";
import { Link } from "react-router";
import {
  formatGTQ
} from "../../lib/catalog";
import {
  getAdminProducts,
  type AdminProduct,
  type AdminProductsResponse
} from "./admin.products.list.api";
import {
  confirmAction,
  showSuccess,
  showError
} from "../../lib/alerts";
import {
  getAdminCategories,
  type AdminCategory
} from "./admin.categories.api";
import {
  createAdminProduct,
  updateAdminProduct,
  deactivateAdminProduct,
  changeVariantPrice
} from "./admin.products.api";
import {
  AdminProductThumbnail
} from "./AdminProductThumbnail";
import {
  reactivateAdminProduct
} from "./admin.products.reactivate.api";
import { AdminVariantsPanel } from "./AdminVariantsPanel";
import type { AdminVariant } from "./admin.variants.api";
type ProductStatusFilter = "all" | "active" | "inactive";

interface EditForm {
  idProducto: number;
  nombre: string;
  idCategoria: number;
  cambiarDescripcion: boolean;
  descripcion: string;
}
interface PriceForm {
  idVariante: number;
  sku: string;
  precioAnterior: string;
  precioNuevo: string;
  motivo: string;
}
const validPrice = (value: string): boolean =>
  /^(?:0|[1-9]\d{0,8})(?:\.\d{1,2})?$/.test(value) &&
  Number(value) > 0;
const errorMessage = (error: unknown): string =>
  error instanceof Error
    ? error.message
    : "Error inesperado";
export function AdminProductsPage() {
  const [categories, setCategories] =
    useState<AdminCategory[]>([]);
  const [categoryError, setCategoryError] =
    useState<string | null>(null);
  const [catalog, setCatalog] =
    useState<AdminProductsResponse | null>(null);
  const [searchDraft, setSearchDraft] = useState("");
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] =
    useState<ProductStatusFilter>("all");
  const [page, setPage] = useState(1);
  const [revision, setRevision] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] =
    useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);
  const [categoryId, setCategoryId] = useState("");
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [sku, setSku] = useState("");
  const [price, setPrice] = useState("");
  const [editing, setEditing] =
    useState<EditForm | null>(null);
  const [priceEditing, setPriceEditing] =
    useState<PriceForm | null>(null);
  const [selectedProduct, setSelectedProduct] =
    useState<AdminProduct | null>(null);
  const [image, setImage] =
    useState<File | null>(null);
  const [imagePreview, setImagePreview] =
    useState<string | null>(null);
  const imageInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!image) {
      setImagePreview(null);
      return;
    }
    const url = URL.createObjectURL(image);
    setImagePreview(url);
    return () => URL.revokeObjectURL(url);
  }, [image]);
  // CARGAR CATEGORÍAS ADMINISTRATIVAS
  useEffect(() => {
    const controller = new AbortController();
    getAdminCategories(controller.signal)
      .then(data => {
        if (!controller.signal.aborted) {
          setCategories(data);
          setCategoryError(null);
        }
      })
      .catch((cause: unknown) => {
        if (!controller.signal.aborted) {
          setCategoryError(errorMessage(cause));
        }
      });
    return () => controller.abort();
  }, [revision]);
  // ==========================================
  // LISTADO ADMINISTRATIVO (PRODUCTOS ACTIVOS E INACTIVOS)
  // ==========================================
  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError(null);
    setCatalog(null);

    getAdminProducts(
      {
        pagina: page,
        tamanoPagina: 10,
        busqueda: search,
        activo: statusFilter === "all"
          ? null
          : statusFilter === "active"
      },
      controller.signal
    )
      .then(data => {
        if (controller.signal.aborted) return;

        if (
          page > 1 &&
          page > data.pagination.totalPaginas
        ) {
          setPage(Math.max(1, data.pagination.totalPaginas));
          return;
        }

        setCatalog(data);
      })
      .catch((cause: unknown) => {
        if (!controller.signal.aborted) {
          setCatalog(null);
          setError(errorMessage(cause));
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [page, search, statusFilter, revision]);

  // OPERACIONES CONFIRMADAS
  async function execute(
    title: string,
    text: string,
    operation: () => Promise<unknown>,
    successText: string,
    danger = false
  ): Promise<boolean> {
    if (busyRef.current) return false;
    busyRef.current = true;
    setBusy(true);
    try {
      const confirmed = await confirmAction({
        title,
        text,
        confirmText: "Sí, continuar",
        danger
      });
      if (!confirmed) return false;
      await operation();
      setRevision(value => value + 1);
      await showSuccess(
        "Operación completada",
        successText
      );
      return true;
    } catch (cause) {
      setRevision(value => value + 1);
      await showError(
        "No se pudo confirmar la operación",
        errorMessage(cause) +
        ". Actualiza el listado antes de reintentar " +
        "si hubo una interrupción de conexión."
      );
      return false;
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }
  // CREAR PRODUCTO Y VARIANTE INICIAL
  async function handleCreate(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();
    const parsedCategory = Number(categoryId);
    const parsedName = name.trim();
    const parsedSku = sku.trim().toUpperCase();
    const parsedPrice = price.trim();
    if (
      !Number.isSafeInteger(parsedCategory) ||
      parsedCategory <= 0 ||
      !categories.some(
        category =>
          category.idCategoria === parsedCategory &&
          category.activa
      )
    ) {
      await showError(
        "Categoría inválida",
        "Selecciona una categoría activa."
      );
      return;
    }
    if (
      parsedName.length < 3 ||
      parsedName.length > 200 ||
      description.trim().length > 2000 ||
      !/^[A-Z0-9._-]{3,64}$/.test(parsedSku) ||
      !validPrice(parsedPrice)
    ) {
      await showError(
        "Datos inválidos",
        "Revisa nombre, descripción, SKU y precio."
      );
      return;
    }
    const selectedImage = image;
    if (!selectedImage) {
      await showError(
        "Imagen requerida",
        "Selecciona una imagen del producto."
      );
      return;
    }
    if (
      !["image/jpeg", "image/png", "image/webp"].includes(selectedImage.type) ||
      selectedImage.size > 3 * 1024 * 1024
    ) {
      await showError(
        "Imagen inválida",
        "Selecciona una imagen JPG, PNG o WebP " +
          "que no supere los 3 MB."
      );
      return;
    }
    const succeeded = await execute(
      "¿Crear producto?",
      `${parsedName} — SKU ${parsedSku}`,
      () => createAdminProduct({
        idCategoria: parsedCategory,
        nombre: parsedName,
        descripcion: description.trim(),
        sku: parsedSku,
        precioActual: parsedPrice,
        imagen: selectedImage
        }),
      "Producto y variante inicial registrados."
    );
    if (succeeded) {
      setName("");
      setDescription("");
      setSku("");
      setPrice("");
      setImage(null);
      if (imageInputRef.current) {
        imageInputRef.current.value = "";
      }
    }
  }
  function startEdit(product: AdminProduct): void {
    setPriceEditing(null);
    setEditing({
      idProducto: product.idProducto,
      nombre: product.nombreProducto,
      idCategoria: product.idCategoria,
      cambiarDescripcion: false,
      descripcion: product.descripcion ?? ""
    });
  }
  // ACTUALIZAR DATOS DEL PRODUCTO
  async function handleUpdate(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();
    if (!editing) return;
    const nombre = editing.nombre.trim();
    if (
      nombre.length < 3 ||
      nombre.length > 200 ||
      editing.descripcion.trim().length > 2000
    ) {
      await showError(
        "Datos inválidos",
        "Revisa el nombre y la descripción."
      );
      return;
    }
    const succeeded = await execute(
      "¿Actualizar producto?",
      `Se modificarán los datos del producto #${editing.idProducto}.`,
      () => updateAdminProduct(
        editing.idProducto,
        {
          nombre,
          idCategoria: editing.idCategoria,
          ...(editing.cambiarDescripcion
            ? {
                descripcion:
                  editing.descripcion.trim() || null
              }
            : {})
        }
      ),
      "Los datos del producto fueron actualizados."
    );
    if (succeeded) setEditing(null);
  }
  // ACTUALIZAR PRECIO CON MOTIVO
  async function handlePrice(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();
    if (!priceEditing) return;
    const nuevo = priceEditing.precioNuevo.trim();
    const motivo = priceEditing.motivo.trim();
    if (
      !validPrice(nuevo) ||
      motivo.length < 3 ||
      motivo.length > 300
    ) {
      await showError(
        "Precio inválido",
        "Ingresa un precio positivo y un motivo de 3 a 300 caracteres."
      );
      return;
    }
    const succeeded = await execute(
      "¿Cambiar precio?",
      `${priceEditing.sku}: ` +
      `${formatGTQ(priceEditing.precioAnterior)} → ` +
      `${formatGTQ(nuevo)}`,
      () => changeVariantPrice(
        priceEditing.idVariante,
        nuevo,
        motivo
      ),
      "Precio verificado y operación registrada."
    );
    if (succeeded) setPriceEditing(null);
  }
  // DESACTIVAR PRODUCTO
  async function handleDeactivate(
    product: AdminProduct
  ): Promise<void> {
    await execute(
      "¿Desactivar producto?",
      `${product.nombreProducto} dejará de estar ` +
      "disponible. También se desactivarán sus variantes.",
      () => deactivateAdminProduct(product.idProducto),
      "Producto desactivado correctamente.",
      true
    );
  }
  // REACTIVAR PRODUCTO (PASO 80B.3)
  async function handleReactivate(
    product: AdminProduct
  ): Promise<void> {
    if (!product.categoriaActiva) {
      await showError(
        "Categoría inactiva",
        "Activa la categoría antes de reactivar el producto."
      );
      return;
    }

    const succeeded = await execute(
      "¿Reactivar producto?",
      `${product.nombreProducto} volverá a estar disponible. ` +
        "Solo se restaurarán las variantes que estaban activas " +
        "antes de su desactivación.",
      () => reactivateAdminProduct(product.idProducto),
      "Estado del producto confirmado. Si estaba inactivo, " +
        "ahora puedes encontrarlo en la pestaña Activos."
    );

    if (succeeded) {
      setEditing(null);
      setPriceEditing(null);
    }
  }

  function handleSearch(
    event: FormEvent<HTMLFormElement>
  ): void {
    event.preventDefault();
    setPage(1);
    setSelectedProduct(null);
    setSearch(searchDraft.trim());
  }
  function handleStatusChange(status: ProductStatusFilter): void {
    setStatusFilter(status);
    setPage(1);
    setSelectedProduct(null);
    setEditing(null);
    setPriceEditing(null);
  }

  const rows = catalog?.items ?? [];
  const pagination = catalog?.pagination;
  const activeCategories =
    categories.filter(category => category.activa);
  return (
    <main className="operator-page">
      <div className="operator-container">
        <Link
          to="/administracion"
          className="orders-back"
        >
          <ArrowLeft size={17} />
          Volver al administrador
        </Link>
        <header className="operator-heading">
          <div>
            <span className="eyebrow">
              SHOPCART / ADMINISTRACIÓN
            </span>
            <h1>Gestión de productos</h1>
            <p>
              Catálogo, variantes iniciales y precios.
            </p>
          </div>
          <Package size={38} />
        </header>
        <section className="admin-product-card">
          <h2>Crear producto</h2>
          {categoryError && (
            <p role="alert">{categoryError}</p>
          )}
          <form
            className="admin-product-form"
            onSubmit={event => {
              void handleCreate(event);
            }}
          >
            <label>
              Categoría
              <select
                required
                value={categoryId}
                onChange={e => setCategoryId(e.target.value)}
                disabled={busy}
              >
                <option value="">Seleccionar</option>
                {activeCategories.map(category => (
                  <option
                    value={category.idCategoria}
                    key={category.idCategoria}
                  >
                    {category.nombre}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Nombre
              <input
                required
                minLength={3}
                maxLength={200}
                value={name}
                onChange={e => setName(e.target.value)}
                disabled={busy}
              />
            </label>
            <label>
              SKU inicial
              <input
                required
                minLength={3}
                maxLength={64}
                placeholder="PROD-001"
                value={sku}
                onChange={e => setSku(e.target.value)}
                disabled={busy}
              />
            </label>
            <label>
              Precio inicial (Q)
              <input
                required
                type="text"
                inputMode="decimal"
                placeholder="150.00"
                value={price}
                onChange={e => setPrice(e.target.value)}
                disabled={busy}
              />
            </label>
            <label className="admin-product-wide">
              Descripción
              <textarea
                maxLength={2000}
                rows={3}
                value={description}
                onChange={e => setDescription(e.target.value)}
                disabled={busy}
              />
            </label>
            <label className="admin-product-wide">
            Imagen principal del producto
            <input
                ref={imageInputRef}
                type="file"
                accept="image/jpeg,image/png,image/webp"
                required
                disabled={busy}
                onChange={event => {
                setImage(
                    event.currentTarget.files?.[0] ?? null
                );
                }}
            />
            <small>
                Formatos: JPG, PNG o WebP.
                Tamaño máximo: 3 MB.
            </small>
            </label>
            {imagePreview && (
            <div className="admin-product-wide">
                <img
                src={imagePreview}
                alt="Vista previa del producto"
                className="admin-product-preview"
                />
            </div>
            )}
            <button
              type="submit"
              className="operator-primary"
              disabled={busy || activeCategories.length === 0}
            >
              Crear producto
            </button>
          </form>
        </section>
        {/* LISTADO ADMINISTRATIVO */}
        <section className="admin-product-card">
          <div className="admin-product-toolbar">
            <div>
              <h2>Administración de productos</h2>
              <p className="admin-product-note">
                Consulta productos activos e inactivos y sus variantes de referencia.
              </p>
            </div>
            <button
              type="button"
              className="operator-refresh"
              disabled={busy || loading}
              onClick={() => setRevision(value => value + 1)}
            >
              <RefreshCw size={16} />
              Actualizar
            </button>
          </div>

          <div
            className="admin-product-status-filter"
            role="group"
            aria-label="Filtrar productos por estado"
          >
            <button
              type="button"
              className={statusFilter === "all" ? "active" : ""}
              aria-pressed={statusFilter === "all"}
              disabled={busy}
              onClick={() => handleStatusChange("all")}
            >
              Todos
            </button>
            <button
              type="button"
              className={statusFilter === "active" ? "active" : ""}
              aria-pressed={statusFilter === "active"}
              disabled={busy}
              onClick={() => handleStatusChange("active")}
            >
              Activos
            </button>
            <button
              type="button"
              className={statusFilter === "inactive" ? "active" : ""}
              aria-pressed={statusFilter === "inactive"}
              disabled={busy}
              onClick={() => handleStatusChange("inactive")}
            >
              Inactivos
            </button>
          </div>

          <form
            className="admin-product-search"
            onSubmit={handleSearch}
          >
            <input
              type="search"
              maxLength={120}
              placeholder="Buscar por nombre o SKU..."
              value={searchDraft}
              disabled={busy}
              onChange={event => setSearchDraft(event.target.value)}
            />
            <button
              type="submit"
              className="operator-primary"
              disabled={loading || busy}
            >
              Buscar
            </button>
          </form>

          {!loading && !error && pagination && (
            <p className="admin-product-note">
              {pagination.totalRegistros} producto(s) encontrado(s).
            </p>
          )}

          {loading ? (
            <p role="status">Cargando productos...</p>
          ) : error ? (
            <p role="alert">{error}</p>
          ) : rows.length === 0 ? (
            <p className="admin-product-note">
              No se encontraron productos con los filtros seleccionados.
            </p>
          ) : (
            <div className="admin-product-table-scroll">
              <table className="admin-product-table">
                <thead>
                  <tr>
                    <th scope="col">Producto</th>
                    <th scope="col">Estado</th>
                    <th scope="col">SKU / Variante</th>
                    <th scope="col">Precio</th>
                    <th scope="col">Existencia</th>
                    <th scope="col">Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map(product => (
                    <tr key={product.idProducto}>
                      <td>
                        <div className="admin-product-identity">
                          <AdminProductThumbnail product={product} />
                          <div>
                            <strong>{product.nombreProducto}</strong>
                            <small>
                              Producto #{product.idProducto}
                              {" · "}
                              {product.nombreCategoria}
                            </small>
                            <small>
                              {product.totalVariantes} variante(s)
                              {" · "}
                              {product.variantesActivas} activa(s)
                            </small>
                          </div>
                        </div>
                      </td>

                      <td>
                        <span
                          className={
                            product.activo
                              ? "admin-product-status active"
                              : "admin-product-status inactive"
                          }
                        >
                          {product.activo ? "Activo" : "Inactivo"}
                        </span>
                      </td>

                      <td>
                        {product.skuReferencia ?? "Sin variante"}
                        <small>
                          {product.idVarianteReferencia === null
                            ? "Sin variante de referencia"
                            : `Variante #${product.idVarianteReferencia}`}
                        </small>
                      </td>

                      <td>
                        {product.precioReferencia === null
                          ? "—"
                          : formatGTQ(product.precioReferencia)}
                      </td>

                      <td>
                        {product.idVarianteReferencia === null
                          ? "—"
                          : product.cantidadFisicaReferencia}
                      </td>

                      <td>
                        <div className="admin-product-actions" style={{ marginBottom: 8 }}>
                          <button
                            type="button"
                            disabled={busy}
                            aria-pressed={selectedProduct?.idProducto === product.idProducto}
                            onClick={() => {
                              setSelectedProduct(current => current?.idProducto === product.idProducto
                                ? null
                                : product);
                              setEditing(null);
                              setPriceEditing(null);
                            }}
                          >
                            <Layers size={15} /> Variantes
                          </button>
                        </div>
                        {product.activo ? (
                          <div className="admin-product-actions">
                            <button
                              type="button"
                              disabled={busy}
                              onClick={() => startEdit(product)}
                            >
                              <Pencil size={15} />
                              Editar
                            </button>

                            <button
                              type="button"
                              disabled={
                                busy ||
                                product.idVarianteReferencia === null ||
                                product.skuReferencia === null ||
                                product.precioReferencia === null ||
                                product.varianteReferenciaActiva !== true
                              }
                              onClick={() => {
                                if (
                                  product.idVarianteReferencia === null ||
                                  product.skuReferencia === null ||
                                  product.precioReferencia === null ||
                                  product.varianteReferenciaActiva !== true
                                ) return;

                                setEditing(null);
                                setPriceEditing({
                                  idVariante: product.idVarianteReferencia,
                                  sku: product.skuReferencia,
                                  precioAnterior: product.precioReferencia,
                                  precioNuevo: product.precioReferencia,
                                  motivo: ""
                                });
                              }}
                            >
                              <Tag size={15} />
                              Precio
                            </button>

                            <button
                              type="button"
                              disabled={busy}
                              onClick={() => void handleDeactivate(product)}
                            >
                              <Power size={15} />
                              Desactivar
                            </button>
                          </div>
                        ) : (
                          <div className="admin-product-actions">
                            <button
                              type="button"
                              disabled={busy || !product.categoriaActiva}
                              title={
                                product.categoriaActiva
                                  ? "Reactivar producto"
                                  : "Activa primero la categoría"
                              }
                              onClick={() => {
                                void handleReactivate(product);
                              }}
                            >
                              <Power size={15} />
                              Reactivar
                            </button>
                            {!product.categoriaActiva && (
                              <span className="admin-product-inactive-note">
                                Activa primero la categoría.
                              </span>
                            )}
                          </div>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {pagination && pagination.totalPaginas > 1 && (
            <nav
              className="orders-pagination"
              aria-label="Paginación de productos"
            >
              <button
                type="button"
                disabled={page <= 1 || busy || loading}
                onClick={() => {
                  setSelectedProduct(null);
                  setPage(current => current - 1);
                }}
              >
                Anterior
              </button>
              <span>
                Página {page} de {pagination.totalPaginas}
              </span>
              <button
                type="button"
                disabled={
                  page >= pagination.totalPaginas ||
                  busy ||
                  loading
                }
                onClick={() => {
                  setSelectedProduct(null);
                  setPage(current => current + 1);
                }}
              >
                Siguiente
              </button>
            </nav>
          )}

          <p className="admin-product-note">
            El precio y la existencia mostrados corresponden a la variante de
            referencia, no a todas las variantes del producto.
          </p>
        </section>

        {selectedProduct && (
          <AdminVariantsPanel
            key={selectedProduct.idProducto}
            product={rows.find(row => row.idProducto === selectedProduct.idProducto) ?? selectedProduct}
            revision={revision}
            onChanged={() => setRevision(value => value + 1)}
            onClose={() => setSelectedProduct(null)}
            onEditPrice={(variant: AdminVariant) => {
              setEditing(null);
              setPriceEditing({
                idVariante: variant.idVariante,
                sku: variant.sku,
                precioAnterior: variant.precioActual,
                precioNuevo: variant.precioActual,
                motivo: ""
              });
            }}
          />
        )}

        {editing && (
          <section className="admin-product-card">
            <h2>Editar producto #{editing.idProducto}</h2>
            <form
              className="admin-product-form"
              onSubmit={event => {
                void handleUpdate(event);
              }}
            >
              <label>
                Nombre
                <input
                  required
                  minLength={3}
                  maxLength={200}
                  value={editing.nombre}
                  disabled={busy}
                  onChange={e => {
                    setEditing(current => current
                      ? { ...current, nombre: e.target.value }
                      : null);
                  }}
                />
              </label>
              <label>
                Categoría
                <select
                  value={editing.idCategoria}
                  disabled={busy}
                  onChange={e => {
                    setEditing(current => current
                      ? {
                          ...current,
                          idCategoria: Number(e.target.value)
                        }
                      : null);
                  }}
                >
                  {categories
                    .filter(category =>
                      category.activa ||
                      category.idCategoria ===
                        editing.idCategoria
                    )
                    .map(category => (
                      <option
                        key={category.idCategoria}
                        value={category.idCategoria}
                      >
                        {category.nombre}
                      </option>
                    ))}
                </select>
              </label>
              <label className="admin-product-wide">
                <input
                  type="checkbox"
                  checked={editing.cambiarDescripcion}
                  disabled={busy}
                  onChange={e => {
                    setEditing(current => current
                      ? {
                          ...current,
                          cambiarDescripcion:
                            e.target.checked
                        }
                      : null);
                  }}
                />
                {" "}Cambiar descripción
              </label>
              {editing.cambiarDescripcion && (
                <label className="admin-product-wide">
                  Nueva descripción
                  <textarea
                    rows={3}
                    maxLength={2000}
                    value={editing.descripcion}
                    disabled={busy}
                    onChange={e => {
                      setEditing(current => current
                        ? {
                            ...current,
                            descripcion: e.target.value
                          }
                        : null);
                    }}
                  />
                </label>
              )}
              <button
                type="submit"
                className="operator-primary"
                disabled={busy}
              >
                Guardar cambios
              </button>
              <button
                type="button"
                className="operator-refresh"
                disabled={busy}
                onClick={() => setEditing(null)}
              >
                Cancelar
              </button>
            </form>
            <p className="admin-product-note">
              La descripción actual viene del listado administrativo.
              Solo se reemplazará cuando actives «Cambiar descripción».
            </p>
          </section>
        )}
        {priceEditing && (
          <section className="admin-product-card">
            <h2>Cambiar precio: {priceEditing.sku}</h2>
            <p>
              Precio actual:{" "}
              {formatGTQ(priceEditing.precioAnterior)}
            </p>
            <form
              className="admin-product-form"
              onSubmit={event => {
                void handlePrice(event);
              }}
            >
              <label>
                Nuevo precio (Q)
                <input
                  required
                  type="text"
                  inputMode="decimal"
                  value={priceEditing.precioNuevo}
                  disabled={busy}
                  onChange={e => {
                    setPriceEditing(current => current
                      ? {
                          ...current,
                          precioNuevo: e.target.value
                        }
                      : null);
                  }}
                />
              </label>
              <label className="admin-product-wide">
                Motivo del cambio
                <textarea
                  required
                  rows={3}
                  minLength={3}
                  maxLength={300}
                  value={priceEditing.motivo}
                  disabled={busy}
                  onChange={e => {
                    setPriceEditing(current => current
                      ? {
                          ...current,
                          motivo: e.target.value
                        }
                      : null);
                  }}
                />
              </label>
              <button
                type="submit"
                className="operator-primary"
                disabled={busy}
              >
                Confirmar nuevo precio
              </button>
              <button
                type="button"
                className="operator-refresh"
                disabled={busy}
                onClick={() => setPriceEditing(null)}
              >
                Cancelar
              </button>
            </form>
          </section>
        )}
      </div>
    </main>
  );
}
