import {
  Link,
  useNavigate
} from "react-router";

import {
  useCart
} from "./features/cart/CartProvider";

import {
  useAuth
} from "./auth/AuthProvider";

import {
  homeForRole
} from "./lib/auth";

import {
  useEffect,
  useMemo,
  useRef,
  useState
} from "react";

import {
  ArrowDownRight,
  ArrowRight,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Heart,
  Layers3,
  Package2,
  RefreshCcw,
  Search,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  X,
  ShoppingBag
} from "lucide-react";

import { ProductCard } from "./components/ProductCard";

import {
  formatGTQ,
  getCategories,
  getProducts,
  type Category,
  type CatalogResponse,
  type Product,
  type Sort
} from "./lib/catalog";

const PAGE_SIZE = 8;

// ==========================================
// HOOK: DEBOUNCE
// ==========================================

function useDebounced<T>(
  value: T,
  delay: number
): T {

  const [debounced, setDebounced] = useState(value);

  useEffect(() => {
    const timer = window.setTimeout(
      () => setDebounced(value),
      delay
    );

    return () => window.clearTimeout(timer);
  }, [value, delay]);

  return debounced;
}

// ==========================================
// NAVEGACION AL CATALOGO
// ==========================================

function scrollToCatalog(): void {
  document
    .getElementById("catalogo")
    ?.scrollIntoView({
      behavior: "smooth"
    });
}

// ==========================================
// MODAL DE DETALLE DE PRODUCTO
// ==========================================

interface ProductDialogProps {
  product: Product;
  onClose: () => void;
  onAdd: (product: Product) => void;
  adding: boolean;
}

function ProductDialog({
  product,
  onClose,
  onAdd,
  adding
}: ProductDialogProps) {

  const closeRef = useRef<HTMLButtonElement>(null);

  // Estado para detectar errores al cargar imágenes
  const [imageFailed, setImageFailed] = useState(false);

  // Restablecer error cuando cambia el producto
  useEffect(() => {
    setImageFailed(false);
  }, [product.imagenUrl]);

  // Manejo de enfoque y tecla Escape
  useEffect(() => {
    closeRef.current?.focus();

    function handleEscape(event: KeyboardEvent) {
      if (event.key === "Escape") {
        onClose();
      }
    }

    window.addEventListener(
      "keydown",
      handleEscape
    );

    return () => {
      window.removeEventListener(
        "keydown",
        handleEscape
      );
    };
  }, [onClose]);
  return (
    <div
      className="modal-backdrop"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) {
          onClose();
        }
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="product-dialog-title"
        className="product-dialog"
      >

        <button
          ref={closeRef}
          className="modal-close icon-button"
          type="button"
          onClick={onClose}
          aria-label="Cerrar detalle"
        >
          <X size={20} />
        </button>

        
        
        <div className="dialog-visual">
          {product.imagenUrl && !imageFailed ? (
            <img
              src={product.imagenUrl}
              alt={
                product.imagenAlt ||
                product.nombreProducto
              }
              loading="lazy"
              onError={() => {
                setImageFailed(true);
              }}
              style={{
                width: "100%",
                height: "100%",
                maxHeight: 340,
                objectFit: "contain"
              }}
            />
          ) : (
            <Package2
              size={88}
              strokeWidth={1}
              aria-hidden="true"
            />
          )}
        </div>


        <div className="dialog-info">

          <span className="eyebrow">
            {product.nombreCategoria}
          </span>

          <h2 id="product-dialog-title">
            {product.nombreProducto}
          </h2>

          <p>Variante: {product.sku}</p>

          <strong>
            {formatGTQ(product.precioActual)}
          </strong>

          <p className="dialog-hint">
            Existencia física registrada:
            {" "}
            {product.cantidadFisica}.
            La disponibilidad real se confirmará
            al reservar inventario.
          </p>

          
            <button
              type="button"
              className="btn btn-primary"
              disabled={
                adding || product.cantidadFisica <= 0
              }
              onClick={() => onAdd(product)}
            >
              <ShoppingBag size={18} />

              {product.cantidadFisica <= 0
                ? "Agotado"
                : "Añadir al carrito"}
            </button>


        </div>

      </section>
    </div>
  );
}

// ==========================================
// COMPONENTE PRINCIPAL
// ==========================================

export default function App() {

  const { session } = useAuth();

  
const navigate = useNavigate();

const {
  itemCount,
  busy: cartBusy,
  loading: cartLoading,
  feedback: cartFeedback,
  addOne
} = useCart();

const [cartActionError, setCartActionError] =
  useState<string | null>(null);

// ==========================================
// AGREGAR PRODUCTO DESDE EL CATALOGO
// ==========================================

function handleAddProduct(product: Product): void {

  if (!session) {
    // El backend actualmente requiere
    // un Cliente autenticado.
    navigate("/login");
    return;
  }

  if (session.user.rol !== "Cliente") {
    setCartActionError(
      "Debes utilizar una cuenta de Cliente para comprar."
    );
    return;
  }

  setCartActionError(null);

  void addOne(product.idVariante);
}


  // ========================================
  // ESTADOS DEL CATALOGO
  // ========================================

  const [categories, setCategories] =
    useState<Category[]>([]);

  const [categoryError, setCategoryError] =
    useState(false);

  const [search, setSearch] = useState("");

  const debouncedSearch = useDebounced(
    search.trim(),
    350
  );

  const [categoryId, setCategoryId] =
    useState<number | null>(null);

  const [sort, setSort] =
    useState<Sort>("name_asc");

  const [onlyAvailable, setOnlyAvailable] =
    useState(false);

  const [minPrice, setMinPrice] = useState("");
  const [maxPrice, setMaxPrice] = useState("");

  const [page, setPage] = useState(1);

  const [result, setResult] =
    useState<CatalogResponse | null>(null);

  const [loading, setLoading] = useState(true);

  const [error, setError] =
    useState<string | null>(null);

  const [retry, setRetry] = useState(0);

  const [selectedProduct, setSelectedProduct] =
    useState<Product | null>(null);

  // ========================================
  // CARGAR CATEGORIAS
  // ========================================

  useEffect(() => {

    const controller = new AbortController();

    getCategories(controller.signal)
      .then((data) => {

        if (controller.signal.aborted) {
          return;
        }

        setCategories(
          data.filter((category) => category.activa)
        );

        setCategoryError(false);
      })
      .catch((cause: unknown) => {

        if (!controller.signal.aborted) {
          console.error(
            "Error al cargar categorias:",
            cause
          );

          setCategoryError(true);
        }
      });

    return () => controller.abort();

  }, []);

  // ========================================
  // VALIDAR FILTROS
  // ========================================

  const invalidPriceRange = useMemo(() => {

    return (
      minPrice !== "" &&
      maxPrice !== "" &&
      Number(minPrice) > Number(maxPrice)
    );

  }, [minPrice, maxPrice]);

  // ========================================
  // CARGAR PRODUCTOS
  // ========================================

  useEffect(() => {

    if (invalidPriceRange) {
      return;
    }

    const controller = new AbortController();

    setLoading(true);
    setError(null);

    getProducts(
      {
        search: debouncedSearch,
        categoryId,
        minPrice,
        maxPrice,
        available: onlyAvailable,
        sort,
        page,
        pageSize: PAGE_SIZE
      },
      controller.signal
    )
      .then((data) => {

        if (!controller.signal.aborted) {
          setResult(data);
        }

      })
      .catch((cause: unknown) => {

        if (controller.signal.aborted) {
          return;
        }

        setError(
          cause instanceof Error
            ? cause.message
            : "Error al cargar el catálogo."
        );

      })
      .finally(() => {

        if (!controller.signal.aborted) {
          setLoading(false);
        }

      });

    return () => controller.abort();

  }, [
    debouncedSearch,
    categoryId,
    minPrice,
    maxPrice,
    onlyAvailable,
    sort,
    page,
    retry,
    invalidPriceRange
  ]);

  // ========================================
  // RESTABLECER FILTROS
  // ========================================

  function resetFilters() {
    setSearch("");
    setCategoryId(null);
    setSort("name_asc");
    setOnlyAvailable(false);
    setMinPrice("");
    setMaxPrice("");
    setPage(1);
  }

  const total =
    result?.pagination.total ?? 0;

  const totalPages =
    result?.pagination.totalPages ?? 0;

  // ========================================
  // RENDERIZAR INTERFAZ
  // ========================================

  return (
    <div className="site-wrapper">

      {/* BARRA SUPERIOR */}

      <div className="announcement">
        <Sparkles size={13} />

        Una nueva forma de explorar tus favoritos

        <span className="announcement-star">
          ✦
        </span>

        ShopCart
      </div>

      {/* NAVEGACION PRINCIPAL */}

      <header className="site-header">

        <div className="container header-inner">

          <a
            className="brand"
            href="#inicio"
            aria-label="ShopCart, ir al inicio"
          >
            <span className="brand-icon">
              <Layers3 size={21} />
            </span>

            <span>
              shop
              <span className="brand-accent">
                cart.
              </span>
            </span>
          </a>

          
          <nav
            className="header-nav"
            aria-label="Navegación principal"
          >
            <Link to="/">Inicio</Link>

            <a href="#catalogo">
              Catálogo
            </a>

            <a href="#beneficios">
              Por qué ShopCart
            </a>

            <Link
              to={
                session
                  ? homeForRole(session.user.rol)
                  : "/login"
              }
            >
              {session
                ? "Mi espacio"
                : "Iniciar sesión"}
            </Link>
          </nav>


          
          <div className="header-actions">

            <Link
              to="/carrito"
              className="header-cart"
              aria-label={`Ir al carrito, ${itemCount} unidades`}
            >
              <ShoppingBag size={20} />

              {itemCount > 0 && (
                <span className="header-cart-count">
                  {itemCount}
                </span>
              )}
            </Link>

            <button
              className="header-cta"
              type="button"
              onClick={scrollToCatalog}
            >
              Explorar tienda
              <ArrowRight size={16} />
            </button>

          </div>


        </div>
      </header>

      <main id="inicio">

        {/* HERO PRINCIPAL */}

        <div className="container">

          <section
            className="hero"
            aria-labelledby="hero-title"
          >

            <div className="hero-copy">

              <span className="eyebrow">
                <span className="eyebrow-dot" />
                ELIGE ALGO EXTRAORDINARIO
              </span>

              <h1 id="hero-title">
                Lo que buscas.
                <br />

                <em>Y algo más.</em>
              </h1>

              <p>
                Un catálogo para descubrir productos
                que encajan contigo. Explora, compara
                y encuentra tu próxima elección.
              </p>

              <div className="hero-actions">

                <button
                  type="button"
                  className="btn btn-primary"
                  onClick={scrollToCatalog}
                >
                  Ver productos
                  <ArrowRight size={18} />
                </button>

                <a
                  className="btn btn-ghost"
                  href="#beneficios"
                >
                  Conoce la experiencia
                  <ArrowDownRight size={17} />
                </a>

              </div>

              <div className="hero-metrics">
                <span className="hero-metric-icon">
                  <CheckCircle2 size={17} />
                </span>

                <span>
                  Precios en quetzales · Catálogo
                  conectado a SQL Server
                </span>
              </div>

            </div>

            {/* ILUSTRACION DECORATIVA */}

            <div
              className="hero-visual"
              aria-hidden="true"
            >

              <div className="visual-grid" />
              <div className="visual-sun" />

              <div className="visual-circle visual-circle-a" />
              <div className="visual-circle visual-circle-b" />

              <div className="visual-card visual-card-main">

                <span className="visual-card-tag">
                  CURATED GOODS / 2026
                </span>

                <Package2
                  size={118}
                  strokeWidth={0.8}
                />

                <span className="visual-card-label">
                  Better everyday.
                </span>

              </div>

              <div className="visual-chip visual-chip-top">
                <Sparkles size={16} />
                Diseñado para descubrir
              </div>

              <div className="visual-chip visual-chip-bottom">
                <span className="visual-chip-dot" />
                Tu próxima elección
              </div>

              <span className="visual-index">
                01 — 03
              </span>

            </div>

          </section>

        </div>

        {/* CARACTERISTICAS */}

        <section
          className="feature-strip"
          id="beneficios"
          aria-label="Características de la tienda"
        >

          <div className="container feature-inner">

            <div>
              <ShieldCheck size={21} />

              <span>
                <strong>Compra confiable</strong>
                <small>
                  Reservas de inventario en checkout
                </small>
              </span>
            </div>

            <div>
              <RefreshCcw size={21} />

              <span>
                <strong>Precios transparentes</strong>
                <small>
                  Importes en quetzales, con IVA
                </small>
              </span>
            </div>

            <div>
              <Heart size={21} />

              <span>
                <strong>Una experiencia para ti</strong>
                <small>
                  Catálogo con filtros y búsqueda
                </small>
              </span>
            </div>

          </div>

        </section>

        {/* CATALOGO */}

        <section
          className="container catalog-section"
          id="catalogo"
          aria-labelledby="catalog-title"
        >

          <div className="section-heading">

            <div>
              <span className="eyebrow">
                DESCUBRE LA COLECCIÓN
              </span>

              <h2 id="catalog-title">
                Encuentra tu próximo
                {" "}
                <em>favorito.</em>
              </h2>

              <p>
                Explora nuestro catálogo en tiempo real.
              </p>
            </div>

            <span className="catalog-count">
              {!loading && !error
                ? `${total} resultados`
                : "Catálogo"}
            </span>

          </div>
            {cartActionError && (
              <div
                className="cart-feedback error"
                role="alert"
              >
                {cartActionError}
              </div>
            )}

            {session?.user.rol === "Cliente" &&
              cartFeedback && (
                <div
                  className={`cart-feedback ${cartFeedback.type}`}
                  role="status"
                >
                  {cartFeedback.message}

                  {cartFeedback.type === "success" && (
                    <>
                      {" "}
                      <Link to="/carrito">
                        Ver mi carrito
                      </Link>
                    </>
                  )}
                </div>
              )}
          <div className="catalog-layout">

            {/* PANEL DE FILTROS */}

            <aside
              className="filters"
              aria-label="Filtros del catálogo"
            >

              <div className="filters-top">

                <span>
                  <SlidersHorizontal size={17} />
                  Filtrar productos
                </span>

                <button
                  type="button"
                  onClick={resetFilters}
                >
                  Limpiar
                </button>

              </div>

              <label
                className="field-label"
                htmlFor="search-products"
              >
                Buscar
              </label>

              <div className="search-field">

                <Search size={18} />

                <input
                  id="search-products"
                  placeholder="Producto o SKU..."
                  value={search}
                  onChange={(event) => {
                    setSearch(event.target.value);
                    setPage(1);
                  }}
                  maxLength={120}
                />

              </div>

              {/* CATEGORIAS */}

              <div className="filter-section">

                <h3>Categorías</h3>

                <div className="category-options">

                  <button
                    type="button"
                    className={
                      categoryId === null
                        ? "category-pill active"
                        : "category-pill"
                    }
                    onClick={() => {
                      setCategoryId(null);
                      setPage(1);
                    }}
                  >
                    Todas las categorías
                    <ArrowRight size={14} />
                  </button>

                  {categories.map((category) => (

                    <button
                      type="button"
                      key={category.idCategoria}
                      className={
                        categoryId === category.idCategoria
                          ? "category-pill active"
                          : "category-pill"
                      }
                      onClick={() => {
                        setCategoryId(category.idCategoria);
                        setPage(1);
                      }}
                    >
                      {category.nombre}
                      <ArrowRight size={14} />
                    </button>

                  ))}

                  {categoryError && (
                    <p className="input-help error">
                      No se pudieron cargar las categorías.
                    </p>
                  )}

                </div>

              </div>

              {/* PRECIO */}

              <div className="filter-section">

                <h3>Rango de precio</h3>

                <div className="price-fields">

                  <label>
                    Desde (Q)

                    <input
                      type="number"
                      min="0"
                      step="0.01"
                      inputMode="decimal"
                      placeholder="0.00"
                      value={minPrice}
                      onChange={(event) => {
                        setMinPrice(event.target.value);
                        setPage(1);
                      }}
                    />
                  </label>

                  <label>
                    Hasta (Q)

                    <input
                      type="number"
                      min="0"
                      step="0.01"
                      inputMode="decimal"
                      placeholder="999.00"
                      value={maxPrice}
                      onChange={(event) => {
                        setMaxPrice(event.target.value);
                        setPage(1);
                      }}
                    />
                  </label>

                </div>

                {invalidPriceRange && (
                  <p className="input-help error">
                    El precio mínimo no puede superar
                    al máximo.
                  </p>
                )}

              </div>

              {/* EXISTENCIA */}

              <div className="filter-section">

                <label className="switch-line">

                  <input
                    type="checkbox"
                    checked={onlyAvailable}
                    onChange={(event) => {
                      setOnlyAvailable(event.target.checked);
                      setPage(1);
                    }}
                  />

                  <span>
                    Solo con existencia física
                  </span>

                </label>

                <p className="input-help">
                  La disponibilidad final se valida
                  al reservar.
                </p>

              </div>

            </aside>

            {/* RESULTADOS */}

            <div className="catalog-results">

              <div className="results-toolbar">

                <span>
                  {!loading && !error
                    ? `${total} productos encontrados`
                    : "Selección de productos"}
                </span>

                <label>
                  Ordenar por
                  {" "}

                  <select
                    value={sort}
                    onChange={(event) => {
                      setSort(event.target.value as Sort);
                      setPage(1);
                    }}
                  >
                    <option value="name_asc">
                      Nombre A–Z
                    </option>

                    <option value="name_desc">
                      Nombre Z–A
                    </option>

                    <option value="price_asc">
                      Precio menor
                    </option>

                    <option value="price_desc">
                      Precio mayor
                    </option>
                  </select>

                </label>

              </div>

              {/* VALIDACION DE PRECIOS */}

              {invalidPriceRange ? (

                <div
                  className="state-panel"
                  role="alert"
                >
                  <SlidersHorizontal size={40} />

                  <h3>
                    Revisa el rango de precios
                  </h3>

                  <p>
                    El valor mínimo debe ser inferior
                    o igual al máximo.
                  </p>
                </div>

              ) : loading ? (

                /* SKELETON LOADING */

                <div
                  className="product-grid"
                  aria-label="Cargando productos"
                  aria-busy="true"
                >
                  {Array.from(
                    { length: 6 },
                    (_, index) => (
                      <div
                        className="skeleton-card"
                        key={index}
                      >
                        <div />
                        <span />
                        <span />
                      </div>
                    )
                  )}
                </div>

              ) : error ? (

                /* ESTADO DE ERROR */

                <div
                  className="state-panel"
                  role="alert"
                >
                  <RefreshCcw size={38} />

                  <h3>
                    No pudimos cargar el catálogo
                  </h3>

                  <p>{error}</p>

                  <button
                    className="btn btn-primary"
                    type="button"
                    onClick={() => {
                      setRetry((value) => value + 1);
                    }}
                  >
                    Reintentar
                    <RefreshCcw size={16} />
                  </button>
                </div>

              ) : result?.data.length ? (

                /* RESULTADOS DEL SERVIDOR */

                <div className="product-grid">

                  {result.data.map((product) => (

                    <ProductCard
                      key={product.idVariante}
                      product={product}
                      onPreview={setSelectedProduct}
                      onAdd={handleAddProduct}
                      adding={
                        session?.user.rol === "Cliente" &&
                        (cartBusy || cartLoading)
                      }
                    />

                  ))}

                </div>

              ) : (

                /* CATALOGO VACIO */

                <div className="state-panel">

                  <Search size={40} />

                  <h3>
                    No encontramos coincidencias
                  </h3>

                  <p>
                    Prueba con otra palabra o
                    modifica los filtros.
                  </p>

                  <button
                    className="btn btn-outline"
                    type="button"
                    onClick={resetFilters}
                  >
                    Restablecer filtros
                  </button>

                </div>

              )}

              {/* PAGINACION */}

              {!loading &&
                !error &&
                !invalidPriceRange &&
                totalPages > 1 && (

                <nav
                  className="pagination"
                  aria-label="Paginación del catálogo"
                >

                  <button
                    type="button"
                    disabled={page <= 1}
                    onClick={() => {
                      setPage((value) => value - 1);
                      scrollToCatalog();
                    }}
                  >
                    <ChevronLeft size={18} />
                    Anterior
                  </button>

                  <span>
                    Página {page} de {totalPages}
                  </span>

                  <button
                    type="button"
                    disabled={page >= totalPages}
                    onClick={() => {
                      setPage((value) => value + 1);
                      scrollToCatalog();
                    }}
                  >
                    Siguiente
                    <ChevronRight size={18} />
                  </button>

                </nav>

              )}

            </div>

          </div>

        </section>

      </main>

      {/* PIE DE PAGINA */}

      <footer className="site-footer">

        <div className="container footer-inner">

          <span className="brand footer-brand">

            <span className="brand-icon">
              <Layers3 size={19} />
            </span>

            shop
            <span className="brand-accent">
              cart.
            </span>

          </span>

          <span>
            Diseñado para comprar con confianza.
          </span>

          <small>
            Tech Challenge 360 · 2026
          </small>

        </div>

      </footer>

      {/* DETALLE DEL PRODUCTO */}

      {selectedProduct && (
      <ProductDialog
        product={selectedProduct}
        onClose={() => setSelectedProduct(null)}
        onAdd={handleAddProduct}
        adding={
          session?.user.rol === "Cliente" &&
          (cartBusy || cartLoading)
        }
        
      />
    )}

    </div>
  );
}
