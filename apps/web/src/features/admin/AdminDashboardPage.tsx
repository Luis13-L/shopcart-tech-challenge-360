import {
  useEffect,
  useState,
  type FormEvent
} from "react";

import {
  ArrowLeft,
  BarChart3,
  CalendarDays,
  Package,
  RefreshCw,
  ShoppingBag,
  TrendingUp,
  Wallet
} from "lucide-react";

import { Link } from "react-router";

import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Tooltip,
  XAxis,
  YAxis
} from "recharts";

import {
  getSalesReport,
  getCategorySalesReport,
  getTopProductsReport,
  type ReportDateRange,
  type SalesGrouping,
  type SalesReportFilters,
  type SalesReportRow,
  type CategorySalesReportRow,
  type TopProductReportRow
} from "./admin.reports.api";

// ==========================================
// TIPOS
// ==========================================

interface DashboardData {
  sales: SalesReportRow[];
  categories: CategorySalesReportRow[];
  products: TopProductReportRow[];
}

// ==========================================
// FECHAS LOCALES
// ==========================================

function toLocalDate(date: Date): string {
  const year = date.getFullYear();

  const month = String(
    date.getMonth() + 1
  ).padStart(2, "0");

  const day = String(
    date.getDate()
  ).padStart(2, "0");

  return `${year}-${month}-${day}`;
}

function initialFilters(): SalesReportFilters {
  const today = new Date();

  const start = new Date(
    today.getFullYear(),
    today.getMonth(),
    today.getDate() - 29
  );

  return {
    fechaInicio: toLocalDate(start),
    fechaFin: toLocalDate(today),
    agrupacion: "DIA"
  };
}

function validDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }

  const date = new Date(
    `${value}T00:00:00.000Z`
  );

  return (
    !Number.isNaN(date.getTime()) &&
    date.toISOString().slice(0, 10) === value &&
    value < "9999-12-31"
  );
}

// ==========================================
// FORMATO DE VALORES
// ==========================================

const currencyFormatter = new Intl.NumberFormat(
  "es-GT",
  {
    style: "currency",
    currency: "GTQ",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  }
);

const numberFormatter = new Intl.NumberFormat(
  "es-GT"
);

// Convertir DECIMAL(19,2) a centavos.
// Evitamos sumar importes con punto flotante.

function toCents(value: string): number {
  const match = value.match(
    /^(-?)(\d+)\.(\d{2})$/
  );

  if (!match) {
    throw new Error(
      "Importe monetario invalido"
    );
  }

  const whole = Number(match[2]);

  const fraction = Number(match[3]);

  const cents = whole * 100 + fraction;

  if (!Number.isSafeInteger(cents)) {
    throw new Error(
      "Importe monetario fuera de rango"
    );
  }

  return match[1] === "-" ? -cents : cents;
}

function money(cents: number): string {
  return currencyFormatter.format(
    cents / 100
  );
}

function compactMoney(cents: number): string {
  return "Q " + new Intl.NumberFormat(
    "es-GT",
    {
      notation: "compact",
      maximumFractionDigits: 1
    }
  ).format(cents / 100);
}

function formatPeriod(
  dateValue: string,
  grouping: SalesGrouping
): string {
  const date = new Date(
    `${dateValue}T12:00:00`
  );

  if (Number.isNaN(date.getTime())) {
    return dateValue;
  }

  if (grouping === "MES") {
    return new Intl.DateTimeFormat(
      "es-GT",
      {
        month: "short",
        year: "numeric"
      }
    ).format(date);
  }

  const label = new Intl.DateTimeFormat(
    "es-GT",
    {
      day: "2-digit",
      month: "2-digit"
    }
  ).format(date);

  return grouping === "SEMANA"
    ? `Sem. ${label}`
    : label;
}

function shortLabel(
  value: string,
  maxLength = 19
): string {
  return value.length > maxLength
    ? `${value.slice(0, maxLength - 1)}…`
    : value;
}

function errorMessage(error: unknown): string {
  return error instanceof Error
    ? error.message
    : "No fue posible consultar los reportes";
}

// ==========================================
// TARJETA DE INDICADOR
// ==========================================

interface MetricCardProps {
  title: string;
  value: string;
  detail: string;
  icon: React.ReactNode;
}

function MetricCard({
  title,
  value,
  detail,
  icon
}: MetricCardProps) {
  return (
    <article className="admin-dashboard-metric">
      <div className="admin-dashboard-metric-icon">
        {icon}
      </div>

      <p>{title}</p>

      <strong>{value}</strong>

      <small>{detail}</small>
    </article>
  );
}

// ==========================================
// DASHBOARD ADMINISTRATIVO
// ==========================================

export function AdminDashboardPage() {
  const [draft, setDraft] =
    useState<SalesReportFilters>(
      initialFilters
    );

  const [filters, setFilters] =
    useState<SalesReportFilters>(
      initialFilters
    );

  const [data, setData] =
    useState<DashboardData | null>(null);

  const [loading, setLoading] =
    useState(true);

  const [error, setError] =
    useState<string | null>(null);

  const [filterError, setFilterError] =
    useState<string | null>(null);

  const [revision, setRevision] =
    useState(0);

  // ========================================
  // 1. CONSULTAR LOS TRES REPORTES
  // ========================================

  useEffect(() => {
    const controller = new AbortController();

    setLoading(true);
    setError(null);

    const range: ReportDateRange = {
      fechaInicio: filters.fechaInicio,
      fechaFin: filters.fechaFin
    };

    Promise.all([
      getSalesReport(
        filters,
        controller.signal
      ),

      getCategorySalesReport(
        range,
        controller.signal
      ),

      getTopProductsReport(
        range,
        controller.signal
      )
    ])
      .then(([sales, categories, products]) => {
        if (controller.signal.aborted) {
          return;
        }

        setData({
          sales,
          categories,
          products
        });
      })
      .catch((cause: unknown) => {
        if (controller.signal.aborted) {
          return;
        }

        setError(errorMessage(cause));
        setData(null);
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => {
      controller.abort();
    };

  }, [filters, revision]);

  // ========================================
  // 2. APLICAR FILTROS
  // ========================================

  function handleApplyFilters(
    event: FormEvent<HTMLFormElement>
  ): void {
    event.preventDefault();

    if (
      !validDate(draft.fechaInicio) ||
      !validDate(draft.fechaFin) ||
      draft.fechaInicio > draft.fechaFin
    ) {
      setFilterError(
        "Selecciona un rango de fechas válido."
      );

      return;
    }

    setFilterError(null);

    setFilters({ ...draft });
  }

  // ========================================
  // 3. PREPARAR DATOS PARA GRAFICAS
  // ========================================

  const salesChart = (data?.sales ?? []).map(
    row => ({
      periodo: formatPeriod(
        row.periodo,
        filters.agrupacion
      ),

      fechaOriginal: row.periodo,
      ventasCentavos: toCents(row.ventasNetas),
      pedidos: row.cantidadPedidos
    })
  );

  const categoryChart = (data?.categories ?? [])
    .map(row => ({
      idCategoria: row.idCategoria,
      nombre: `Categoría #${row.idCategoria}`,
      ventasCentavos: toCents(row.ventasNetas),
      unidades: row.unidadesNetas
    }))
    .sort(
      (a, b) =>
        b.ventasCentavos - a.ventasCentavos
    )
    .slice(0, 8);

  const productsChart = (data?.products ?? [])
    .map(row => ({
      idVariante: row.idVariante,
      nombre: row.nombreProducto,
      etiqueta: shortLabel(
        row.nombreProducto,
        22
      ),
      unidades: row.unidadesVendidas,
      ventasCentavos: toCents(row.ventasNetas)
    }));

  // ========================================
  // 4. CALCULAR INDICADORES
  // ========================================

  const totalSalesCents = salesChart.reduce(
    (sum, row) => sum + row.ventasCentavos,
    0
  );

  const totalOrders = salesChart.reduce(
    (sum, row) => sum + row.pedidos,
    0
  );

  // Las categorias del reporte abarcan
  // todas las unidades netas del periodo.
  // No sumar solo el top 10 de productos.

  const totalUnits = (
    data?.categories ?? []
  ).reduce(
    (sum, row) => sum + row.unidadesNetas,
    0
  );

  const averageTicketCents =
    totalOrders > 0
      ? Math.round(
          totalSalesCents / totalOrders
        )
      : 0;

  // ========================================
  // 5. INTERFAZ
  // ========================================

  return (
    <main className="operator-page">
      <div className="operator-container">

        <Link
          to="/administracion"
          className="orders-back"
        >
          <ArrowLeft size={18} />
          Volver al administrador
        </Link>

        <header className="operator-heading">
          <div>
            <span className="eyebrow">
              SHOPCART / ADMINISTRACIÓN
            </span>

            <h1>Dashboard de ventas</h1>

            <p>
              Analiza el desempeño comercial,
              categorías y productos.
            </p>
          </div>

          <BarChart3 size={38} />
        </header>

        {/* ==================================
            FILTROS DE PERIODO
        ================================== */}

        <section className="admin-dashboard-card">
          <div className="admin-dashboard-heading">
            <div>
              <h2>Período de análisis</h2>

              <p>
                Consulta información de ventas
                y pedidos elegibles.
              </p>
            </div>

            <CalendarDays size={23} />
          </div>

          <form
            className="admin-dashboard-filters"
            onSubmit={handleApplyFilters}
          >
            <label>
              Fecha inicial

              <input
                type="date"
                required
                value={draft.fechaInicio}
                onChange={event => {
                  setDraft(current => ({
                    ...current,
                    fechaInicio: event.target.value
                  }));
                }}
              />
            </label>

            <label>
              Fecha final

              <input
                type="date"
                required
                value={draft.fechaFin}
                onChange={event => {
                  setDraft(current => ({
                    ...current,
                    fechaFin: event.target.value
                  }));
                }}
              />
            </label>

            <label>
              Agrupación

              <select
                value={draft.agrupacion}
                onChange={event => {
                  setDraft(current => ({
                    ...current,
                    agrupacion:
                      event.target.value as SalesGrouping
                  }));
                }}
              >
                <option value="DIA">
                  Por día
                </option>

                <option value="SEMANA">
                  Por semana
                </option>

                <option value="MES">
                  Por mes
                </option>
              </select>
            </label>

            <button
              type="submit"
              className="operator-primary"
              disabled={loading}
            >
              <TrendingUp size={17} />
              Aplicar filtros
            </button>

            <button
              type="button"
              className="operator-refresh"
              disabled={loading}
              onClick={() => {
                setRevision(value => value + 1);
              }}
            >
              <RefreshCw size={17} />
              Actualizar
            </button>
          </form>

          {filterError && (
            <p role="alert" className="auth-error">
              {filterError}
            </p>
          )}
        </section>

        {/* ==================================
            CARGA Y ERRORES
        ================================== */}

        {loading ? (
          <section
            className="admin-dashboard-card admin-dashboard-empty"
            role="status"
          >
            <span className="auth-spinner" />
            <p>Cargando reportes...</p>
          </section>

        ) : error ? (
          <section
            className="admin-dashboard-card admin-dashboard-empty"
            role="alert"
          >
            <p>{error}</p>

            <button
              type="button"
              className="operator-primary"
              onClick={() => {
                setRevision(value => value + 1);
              }}
            >
              Reintentar
            </button>
          </section>

        ) : data ? (
          <>
            {/* ==============================
                INDICADORES
            ============================== */}

            <section
              className="admin-dashboard-metrics"
              aria-label="Indicadores comerciales"
            >
              <MetricCard
                title="Ventas netas"
                value={money(totalSalesCents)}
                detail="Descuentos y devoluciones incluidos"
                icon={<Wallet size={23} />}
              />

              <MetricCard
                title="Pedidos elegibles"
                value={numberFormatter.format(totalOrders)}
                detail="Entregados o con devoluciones"
                icon={<ShoppingBag size={23} />}
              />

              <MetricCard
                title="Ticket neto promedio"
                value={money(averageTicketCents)}
                detail="Ventas netas / pedidos elegibles"
                icon={<TrendingUp size={23} />}
              />

              <MetricCard
                title="Unidades netas"
                value={numberFormatter.format(totalUnits)}
                detail="Productos netos por categoría"
                icon={<Package size={23} />}
              />
            </section>

            {/* ==============================
                GRAFICA DE VENTAS
            ============================== */}

            <section className="admin-dashboard-card">
              <div className="admin-dashboard-heading">
                <div>
                  <h2>Evolución de ventas netas</h2>

                  <p>
                    Ventas agrupadas por{" "}
                    {filters.agrupacion === "DIA"
                      ? "día"
                      : filters.agrupacion === "SEMANA"
                        ? "semana"
                        : "mes"}.
                  </p>
                </div>
              </div>

              {salesChart.length === 0 ? (
                <div className="admin-dashboard-empty">
                  No existen ventas elegibles
                  en el período seleccionado.
                </div>
              ) : (
                <div className="admin-dashboard-chart">
                  <AreaChart
                    responsive
                    style={{
                      width: "100%",
                      height: 320
                    }}
                    data={salesChart}
                    margin={{
                      top: 15,
                      right: 20,
                      bottom: 10,
                      left: 10
                    }}
                  >
                    <CartesianGrid
                      stroke="#eeeaf5"
                      strokeDasharray="3 3"
                    />

                    <XAxis
                      dataKey="periodo"
                      tick={{
                        fill: "#85899b",
                        fontSize: 11
                      }}
                    />

                    <YAxis
                      tickFormatter={value =>
                        compactMoney(Number(value))
                      }
                      tick={{
                        fill: "#85899b",
                        fontSize: 11
                      }}
                      width={75}
                    />

                    <Tooltip
                      formatter={value =>
                        money(Number(value))
                      }
                    />

                    <Area
                      name="Ventas netas"
                      type="monotone"
                      dataKey="ventasCentavos"
                      stroke="#7162ed"
                      fill="#7162ed"
                      fillOpacity={0.14}
                      strokeWidth={3}
                    />
                  </AreaChart>
                </div>
              )}

              <p className="admin-dashboard-note">
                Solo se muestran períodos con
                movimientos incluidos en el reporte.
              </p>
            </section>

            {/* ==============================
                CATEGORIAS Y PRODUCTOS
            ============================== */}

            <div className="admin-dashboard-grid">

              {/* VENTAS POR CATEGORIA */}

              <section className="admin-dashboard-card">
                <div className="admin-dashboard-heading">
                  <div>
                    <h2>Ventas por categoría</h2>

                    <p>
                      Hasta ocho categorías
                      con mayores ventas netas.
                    </p>
                  </div>
                </div>

                {categoryChart.length === 0 ? (
                  <div className="admin-dashboard-empty">
                    Sin ventas por categoría
                    en este período.
                  </div>
                ) : (
                  <div className="admin-dashboard-chart">
                    <BarChart
                      responsive
                      layout="vertical"
                      style={{
                        width: "100%",
                        height: Math.max(
                          280,
                          categoryChart.length * 48
                        )
                      }}
                      data={categoryChart}
                      margin={{
                        top: 10,
                        right: 20,
                        bottom: 10,
                        left: 10
                      }}
                    >
                      <CartesianGrid
                        stroke="#eeeaf5"
                        strokeDasharray="3 3"
                      />

                      <XAxis
                        type="number"
                        tickFormatter={value =>
                          compactMoney(Number(value))
                        }
                        tick={{
                          fill: "#85899b",
                          fontSize: 11
                        }}
                      />

                      <YAxis
                        dataKey="nombre"
                        type="category"
                        width={115}
                        tick={{
                          fill: "#85899b",
                          fontSize: 11
                        }}
                      />

                      <Tooltip
                        formatter={value =>
                          money(Number(value))
                        }
                      />

                      <Bar
                        name="Ventas netas"
                        dataKey="ventasCentavos"
                        fill="#7162ed"
                        radius={[0, 6, 6, 0]}
                      />
                    </BarChart>
                  </div>
                )}

                <p className="admin-dashboard-note">
                  Las categorías se identifican
                  mediante su ID registrado.
                </p>
              </section>

              {/* TOP PRODUCTOS */}

              <section className="admin-dashboard-card">
                <div className="admin-dashboard-heading">
                  <div>
                    <h2>Top 10 productos</h2>

                    <p>
                      Clasificados por unidades
                      netas vendidas.
                    </p>
                  </div>
                </div>

                {productsChart.length === 0 ? (
                  <div className="admin-dashboard-empty">
                    No existen productos vendidos
                    en el período seleccionado.
                  </div>
                ) : (
                  <div className="admin-dashboard-chart">
                    <BarChart
                      responsive
                      layout="vertical"
                      style={{
                        width: "100%",
                        height: Math.max(
                          280,
                          productsChart.length * 45
                        )
                      }}
                      data={productsChart}
                      margin={{
                        top: 10,
                        right: 20,
                        bottom: 10,
                        left: 10
                      }}
                    >
                      <CartesianGrid
                        stroke="#eeeaf5"
                        strokeDasharray="3 3"
                      />

                      <XAxis
                        type="number"
                        allowDecimals={false}
                        tick={{
                          fill: "#85899b",
                          fontSize: 11
                        }}
                      />

                      <YAxis
                        dataKey="etiqueta"
                        type="category"
                        width={125}
                        tick={{
                          fill: "#85899b",
                          fontSize: 11
                        }}
                      />

                      <Tooltip
                        formatter={value =>
                          numberFormatter.format(
                            Number(value)
                          ) + " unidades"
                        }
                      />

                      <Bar
                        name="Unidades netas"
                        dataKey="unidades"
                        fill="#28a879"
                        radius={[0, 6, 6, 0]}
                      />
                    </BarChart>
                  </div>
                )}

                <p className="admin-dashboard-note">
                  El ranking utiliza las variantes
                  y unidades devueltas por SQL Server.
                </p>
              </section>

            </div>
          </>
        ) : null}

      </div>
    </main>
  );
}
