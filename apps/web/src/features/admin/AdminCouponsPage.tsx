import {
  useEffect,
  useRef,
  useState,
  type FormEvent
} from "react";

import {
  ArrowLeft,
  Pencil,
  Plus,
  Power,
  RefreshCw,
  TicketPercent
} from "lucide-react";

import { Link } from "react-router";

import {
  confirmAction,
  showError,
  showSuccess
} from "../../lib/alerts";

import { formatGTQ } from "../../lib/catalog";

import {
  getAdminCategories,
  type AdminCategory
} from "./admin.categories.api";

import {
  assignCouponCategory,
  changeCouponStatus,
  createAdminCoupon,
  getAdminCoupons,
  updateAdminCoupon,
  type AdminCoupon,
  type CouponInput,
  type DiscountType
} from "./admin.coupons.api";

interface CouponForm {
  codigo: string;
  tipoDescuento: DiscountType;
  valor: string;
  montoMinimo: string;
  limiteUsos: string;
  limitePorCliente: string;
  fechaInicio: string;
  fechaFin: string;
  activo: boolean;
  categoria: string;
}

function toLocalInput(value: Date): string {
  const local = new Date(
    value.getTime() -
    value.getTimezoneOffset() * 60_000
  );

  return local.toISOString().slice(0, 16);
}

function initialForm(): CouponForm {
  const now = new Date();
  const end = new Date(
    now.getTime() + 30 * 24 * 60 * 60 * 1000
  );

  return {
    codigo: "",
    tipoDescuento: "PORCENTAJE",
    valor: "10",
    montoMinimo: "0",
    limiteUsos: "100",
    limitePorCliente: "1",
    fechaInicio: toLocalInput(now),
    fechaFin: toLocalInput(end),
    activo: true,
    categoria: ""
  };
}

function messageFrom(error: unknown): string {
  return error instanceof Error
    ? error.message
    : "No fue posible completar la operación";
}

function validMoney(value: string): boolean {
  return /^(0|[1-9]\d{0,8})(?:\.\d{1,2})?$/
    .test(value);
}

function validInteger(value: string): boolean {
  return /^[1-9]\d*$/.test(value) &&
    Number.isSafeInteger(Number(value)) &&
    Number(value) <= 2147483647;
}

function toInput(form: CouponForm): CouponInput {
  const codigo = form.codigo.trim().toUpperCase();
  const inicio = new Date(form.fechaInicio);
  const fin = new Date(form.fechaFin);

  if (!/^[A-Z0-9_-]{3,50}$/.test(codigo)) {
    throw new Error(
      "El código debe tener entre 3 y 50 " +
      "caracteres: letras, números, _ o -."
    );
  }

  if (
    !validMoney(form.valor) ||
    Number(form.valor) <= 0 ||
    (
      form.tipoDescuento === "PORCENTAJE" &&
      Number(form.valor) > 100
    )
  ) {
    throw new Error("Valor del descuento inválido.");
  }

  if (!validMoney(form.montoMinimo)) {
    throw new Error("Monto mínimo inválido.");
  }

  if (
    !validInteger(form.limiteUsos) ||
    !validInteger(form.limitePorCliente)
  ) {
    throw new Error(
      "Los límites de uso deben ser enteros positivos."
    );
  }

  if (
    Number.isNaN(inicio.getTime()) ||
    Number.isNaN(fin.getTime()) ||
    fin <= inicio
  ) {
    throw new Error(
      "La fecha final debe ser posterior a la inicial."
    );
  }

  return {
    codigo,
    tipoDescuento: form.tipoDescuento,
    valor: Number(form.valor),
    montoMinimo: Number(form.montoMinimo),
    limiteUsos: Number(form.limiteUsos),
    limitePorCliente: Number(form.limitePorCliente),
    fechaInicio: inicio.toISOString(),
    fechaFin: fin.toISOString(),
    activo: form.activo
  };
}

function formatDate(value: string): string {
  return new Intl.DateTimeFormat("es-GT", {
    dateStyle: "medium",
    timeStyle: "short"
  }).format(new Date(value));
}

function discountLabel(coupon: AdminCoupon): string {
  return coupon.tipoDescuento === "PORCENTAJE"
    ? `${coupon.valor}%`
    : formatGTQ(coupon.valor);
}

export function AdminCouponsPage() {
  const [coupons, setCoupons] =
    useState<AdminCoupon[]>([]);

  const [categories, setCategories] =
    useState<AdminCategory[]>([]);

  const [form, setForm] =
    useState<CouponForm>(initialForm);

  const [editingId, setEditingId] =
    useState<number | null>(null);

  const [scopeId, setScopeId] =
    useState<number | null>(null);

  const [scopeCategory, setScopeCategory] =
    useState("");

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const lock = useRef(false);

  const [revision, setRevision] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const [search, setSearch] = useState("");
  const [status, setStatus] =
    useState("TODOS");

  useEffect(() => {
    const controller = new AbortController();

    setLoading(true);
    setError(null);

    Promise.all([
      getAdminCoupons(controller.signal),
      getAdminCategories(controller.signal)
    ])
      .then(([couponData, categoryData]) => {
        if (controller.signal.aborted) return;

        setCoupons(couponData);
        setCategories(categoryData);
      })
      .catch((cause: unknown) => {
        if (!controller.signal.aborted) {
          setError(messageFrom(cause));
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [revision]);

  function refresh(): void {
    setRevision(value => value + 1);
  }

  function changeField<K extends keyof CouponForm>(
    field: K,
    value: CouponForm[K]
  ): void {
    setForm(current => ({
      ...current,
      [field]: value
    }));
  }

  function resetForm(): void {
    setEditingId(null);
    setForm(initialForm());
  }

  function startEdit(coupon: AdminCoupon): void {
    if (lock.current) return;

    setScopeId(null);
    setEditingId(coupon.idCupon);

    setForm({
      codigo: coupon.codigo,
      tipoDescuento: coupon.tipoDescuento,
      valor: coupon.valor,
      montoMinimo: coupon.montoMinimo,
      limiteUsos: String(coupon.limiteUsos),
      limitePorCliente: String(
        coupon.limitePorCliente
      ),
      fechaInicio: toLocalInput(
        new Date(coupon.fechaInicio)
      ),
      fechaFin: toLocalInput(
        new Date(coupon.fechaFin)
      ),
      activo: coupon.activo,
      categoria:
        coupon.idCategoriaAplicable?.toString() ?? ""
    });
  }

  async function handleSave(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();

    if (lock.current) return;

    let input: CouponInput;

    try {
      input = toInput(form);
    } catch (cause) {
      await showError(
        "Datos inválidos",
        messageFrom(cause)
      );
      return;
    }

    const categoryId =
      form.categoria === ""
        ? null
        : Number(form.categoria);

    if (
      editingId === null &&
      categoryId !== null &&
      (
        !Number.isSafeInteger(categoryId) ||
        categoryId <= 0 ||
        !categories.some(
          category =>
            category.idCategoria === categoryId &&
            category.activa
        )
      )
    ) {
      await showError(
        "Categoría inválida",
        "Selecciona una categoría activa."
      );
      return;
    }

    const confirmed = await confirmAction({
      title: editingId === null
        ? "¿Crear cupón?"
        : "¿Actualizar cupón?",
      text: `Código: ${input.codigo}`,
      confirmText: editingId === null
        ? "Crear cupón"
        : "Guardar cambios"
    });

    if (!confirmed) return;

    lock.current = true;
    setSaving(true);

    try {
      if (editingId !== null) {
        // El alcance se modifica por separado.
        await updateAdminCoupon(editingId, input);
      } else if (categoryId === null) {
        await createAdminCoupon(input);
      } else {
        // Evita dejar activo un cupón general
        // cuando todavía no tiene su categoría.
        const created = await createAdminCoupon({
          ...input,
          activo: false
        });

        await assignCouponCategory(
          created.idCupon,
          categoryId
        );

        if (input.activo) {
          await changeCouponStatus(
            created.idCupon,
            true
          );
        }
      }

      resetForm();
      refresh();

      await showSuccess(
        editingId === null
          ? "Cupón creado"
          : "Cupón actualizado",
        "Los cambios quedaron registrados."
      );
    } catch (cause) {
      refresh();

      await showError(
        "No se pudo completar la operación",
        messageFrom(cause) +
          " Revisa el listado antes de reintentar; " +
          "el cupón pudo quedar creado e inactivo."
      );
    } finally {
      lock.current = false;
      setSaving(false);
    }
  }

  async function handleStatus(
    coupon: AdminCoupon
  ): Promise<void> {
    if (lock.current) return;

    const desired = !coupon.activo;

    const confirmed = await confirmAction({
      title: desired
        ? "¿Activar cupón?"
        : "¿Desactivar cupón?",
      text: `Código: ${coupon.codigo}`,
      confirmText: desired
        ? "Activar"
        : "Desactivar",
      danger: !desired
    });

    if (!confirmed) return;

    lock.current = true;
    setSaving(true);

    try {
      await changeCouponStatus(
        coupon.idCupon,
        desired
      );

      refresh();

      await showSuccess(
        "Estado actualizado",
        "La operación se realizó correctamente."
      );
    } catch (cause) {
      refresh();
      await showError(
        "No se pudo cambiar el estado",
        messageFrom(cause)
      );
    } finally {
      lock.current = false;
      setSaving(false);
    }
  }

  function startScope(coupon: AdminCoupon): void {
    if (lock.current) return;

    resetForm();
    setScopeId(coupon.idCupon);
    setScopeCategory(
      coupon.idCategoriaAplicable?.toString() ?? ""
    );
  }

  async function handleScope(
    event: FormEvent<HTMLFormElement>
  ): Promise<void> {
    event.preventDefault();

    if (scopeId === null || lock.current) return;

    const categoryId =
      scopeCategory === ""
        ? null
        : Number(scopeCategory);

    if (
      categoryId !== null &&
      !categories.some(
        category =>
          category.idCategoria === categoryId &&
          category.activa
      )
    ) {
      await showError(
        "Categoría inválida",
        "Selecciona una categoría activa."
      );
      return;
    }

    const confirmed = await confirmAction({
      title: "¿Cambiar alcance del cupón?",
      text: categoryId === null
        ? "El cupón podrá aplicarse al carrito completo."
        : "El cupón aplicará únicamente a la categoría seleccionada.",
      confirmText: "Cambiar alcance"
    });

    if (!confirmed) return;

    lock.current = true;
    setSaving(true);

    try {
      await assignCouponCategory(
        scopeId,
        categoryId
      );

      setScopeId(null);
      refresh();

      await showSuccess(
        "Alcance actualizado",
        "La categoría del cupón se guardó."
      );
    } catch (cause) {
      refresh();

      await showError(
        "No se pudo cambiar el alcance",
        messageFrom(cause)
      );
    } finally {
      lock.current = false;
      setSaving(false);
    }
  }

  const filtered = coupons.filter(coupon => {
    const matchesText =
      coupon.codigo.toLowerCase()
        .includes(search.trim().toLowerCase()) ||
      String(coupon.idCupon) === search.trim();

    const matchesStatus =
      status === "TODOS" ||
      (status === "ACTIVOS" && coupon.activo) ||
      (status === "INACTIVOS" && !coupon.activo);

    return matchesText && matchesStatus;
  });

  const scopeCoupon = coupons.find(
    coupon => coupon.idCupon === scopeId
  );

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
            <h1>Cupones y promociones</h1>
            <p>
              Descuentos, vigencia, límites de uso
              y categorías aplicables.
            </p>
          </div>
          <TicketPercent size={38} />
        </header>

        <div className="admin-coupon-layout">
          <section className="admin-coupon-panel">
            <div className="admin-coupon-heading">
              <h2>
                {editingId === null
                  ? "Crear cupón"
                  : `Editar cupón #${editingId}`}
              </h2>

              {editingId !== null && (
                <button
                  type="button"
                  disabled={saving}
                  onClick={resetForm}
                >
                  Cancelar edición
                </button>
              )}
            </div>

            <form
              className="admin-coupon-form"
              onSubmit={event => {
                void handleSave(event);
              }}
            >
              <label>
                Código
                <input
                  required
                  maxLength={50}
                  value={form.codigo}
                  disabled={saving}
                  placeholder="DESCUENTO10"
                  onChange={event =>
                    changeField(
                      "codigo",
                      event.target.value.toUpperCase()
                    )
                  }
                />
              </label>

              <label>
                Tipo de descuento
                <select
                  value={form.tipoDescuento}
                  disabled={saving}
                  onChange={event =>
                    changeField(
                      "tipoDescuento",
                      event.target.value as DiscountType
                    )
                  }
                >
                  <option value="PORCENTAJE">
                    Porcentaje
                  </option>
                  <option value="MONTO_FIJO">
                    Monto fijo
                  </option>
                </select>
              </label>

              <div className="admin-coupon-two">
                <label>
                  {form.tipoDescuento === "PORCENTAJE"
                    ? "Descuento (%)"
                    : "Descuento (Q)"}
                  <input
                    required
                    type="number"
                    min="0.01"
                    max={form.tipoDescuento === "PORCENTAJE"
                      ? "100"
                      : undefined}
                    step="0.01"
                    value={form.valor}
                    disabled={saving}
                    onChange={event =>
                      changeField(
                        "valor",
                        event.target.value
                      )
                    }
                  />
                </label>

                <label>
                  Compra mínima (Q)
                  <input
                    required
                    type="number"
                    min="0"
                    step="0.01"
                    value={form.montoMinimo}
                    disabled={saving}
                    onChange={event =>
                      changeField(
                        "montoMinimo",
                        event.target.value
                      )
                    }
                  />
                </label>
              </div>

              <div className="admin-coupon-two">
                <label>
                  Límite total de usos
                  <input
                    required
                    type="number"
                    min="1"
                    step="1"
                    value={form.limiteUsos}
                    disabled={saving}
                    onChange={event =>
                      changeField(
                        "limiteUsos",
                        event.target.value
                      )
                    }
                  />
                </label>

                <label>
                  Límite por cliente
                  <input
                    required
                    type="number"
                    min="1"
                    step="1"
                    value={form.limitePorCliente}
                    disabled={saving}
                    onChange={event =>
                      changeField(
                        "limitePorCliente",
                        event.target.value
                      )
                    }
                  />
                </label>
              </div>

              <div className="admin-coupon-two">
                <label>
                  Inicio
                  <input
                    required
                    type="datetime-local"
                    value={form.fechaInicio}
                    disabled={saving}
                    onChange={event =>
                      changeField(
                        "fechaInicio",
                        event.target.value
                      )
                    }
                  />
                </label>

                <label>
                  Vencimiento
                  <input
                    required
                    type="datetime-local"
                    value={form.fechaFin}
                    disabled={saving}
                    onChange={event =>
                      changeField(
                        "fechaFin",
                        event.target.value
                      )
                    }
                  />
                </label>
              </div>

              <label>
                Categoría aplicable
                <select
                  value={form.categoria}
                  disabled={saving || editingId !== null}
                  onChange={event =>
                    changeField(
                      "categoria",
                      event.target.value
                    )
                  }
                >
                  <option value="">
                    Todas las categorías
                  </option>

                  {categories
                    .filter(category =>
                      category.activa ||
                      String(category.idCategoria) ===
                        form.categoria
                    )
                    .map(category => (
                      <option
                        key={category.idCategoria}
                        value={category.idCategoria}
                        disabled={!category.activa}
                      >
                        {category.nombre}
                      </option>
                    ))}
                </select>

                {editingId !== null && (
                  <small>
                    Para modificar la categoría de un
                    cupón existente, utiliza «Alcance».
                  </small>
                )}
              </label>

              <label className="admin-coupon-check">
                <input
                  type="checkbox"
                  checked={form.activo}
                  disabled={saving}
                  onChange={event =>
                    changeField(
                      "activo",
                      event.target.checked
                    )
                  }
                />
                Habilitar cupón
              </label>

              <button
                type="submit"
                className="operator-primary"
                disabled={saving || loading}
              >
                <Plus size={17} />
                {saving
                  ? "Guardando..."
                  : editingId === null
                    ? "Crear cupón"
                    : "Guardar cambios"}
              </button>
            </form>
          </section>

          <section className="admin-coupon-panel">
            <div className="admin-coupon-heading">
              <h2>Cupones registrados</h2>

              <button
                type="button"
                className="operator-refresh"
                disabled={saving || loading}
                onClick={refresh}
              >
                <RefreshCw size={16} />
                Actualizar
              </button>
            </div>

            <div className="admin-coupon-filters">
              <input
                type="search"
                placeholder="Buscar por código o ID..."
                value={search}
                onChange={event =>
                  setSearch(event.target.value)
                }
              />

              <select
                value={status}
                onChange={event =>
                  setStatus(event.target.value)
                }
              >
                <option value="TODOS">Todos</option>
                <option value="ACTIVOS">Habilitados</option>
                <option value="INACTIVOS">Deshabilitados</option>
              </select>
            </div>

            {loading ? (
              <p role="status">
                Cargando cupones...
              </p>
            ) : error ? (
              <p role="alert">
                {error}
              </p>
            ) : filtered.length === 0 ? (
              <p>
                No se encontraron cupones.
              </p>
            ) : (
              <div className="admin-coupon-list">
                {filtered.map(coupon => {
                  const category = categories.find(
                    item =>
                      item.idCategoria ===
                      coupon.idCategoriaAplicable
                  );

                  return (
                    <article
                      className="admin-coupon-item"
                      key={coupon.idCupon}
                    >
                      <div className="admin-coupon-item-top">
                        <div>
                          <small>
                            CUPÓN #{coupon.idCupon}
                          </small>
                          <h3>{coupon.codigo}</h3>
                        </div>

                        <span
                          className={
                            coupon.activo
                              ? "admin-coupon-status enabled"
                              : "admin-coupon-status disabled"
                          }
                        >
                          {coupon.activo
                            ? "Habilitado"
                            : "Deshabilitado"}
                        </span>
                      </div>

                      <div className="admin-coupon-amount">
                        {discountLabel(coupon)}
                        <small>
                          {coupon.tipoDescuento === "PORCENTAJE"
                            ? " de descuento"
                            : " de descuento fijo"}
                        </small>
                      </div>

                      <div className="admin-coupon-facts">
                        <span>
                          Mínimo: {formatGTQ(coupon.montoMinimo)}
                        </span>
                        <span>
                          Usos: {coupon.usosRealizados}
                          /{coupon.limiteUsos}
                        </span>
                        <span>
                          Por cliente: {coupon.limitePorCliente}
                        </span>
                        <span>
                          Categoría: {category?.nombre ?? (
                            coupon.idCategoriaAplicable === null
                              ? "Todas"
                              : `#${coupon.idCategoriaAplicable}`
                          )}
                        </span>
                        <span>
                          Vence: {formatDate(coupon.fechaFin)}
                        </span>
                      </div>

                      <div className="admin-coupon-actions">
                        <button
                          type="button"
                          disabled={saving}
                          onClick={() => startEdit(coupon)}
                        >
                          <Pencil size={15} />
                          Editar
                        </button>

                        <button
                          type="button"
                          disabled={saving}
                          onClick={() => startScope(coupon)}
                        >
                          Alcance
                        </button>

                        <button
                          type="button"
                          disabled={saving}
                          onClick={() => {
                            void handleStatus(coupon);
                          }}
                        >
                          <Power size={15} />
                          {coupon.activo
                            ? "Desactivar"
                            : "Activar"}
                        </button>
                      </div>
                    </article>
                  );
                })}
              </div>
            )}

            {scopeCoupon && (
              <form
                className="admin-coupon-scope"
                onSubmit={event => {
                  void handleScope(event);
                }}
              >
                <h3>
                  Alcance de {scopeCoupon.codigo}
                </h3>

                <label>
                  Categoría
                  <select
                    value={scopeCategory}
                    disabled={saving}
                    onChange={event =>
                      setScopeCategory(event.target.value)
                    }
                  >
                    <option value="">
                      Todas las categorías
                    </option>

                    {categories
                      .filter(category =>
                        category.activa ||
                        String(category.idCategoria) ===
                          scopeCategory
                      )
                      .map(category => (
                        <option
                          key={category.idCategoria}
                          value={category.idCategoria}
                          disabled={!category.activa}
                        >
                          {category.nombre}
                        </option>
                      ))}
                  </select>
                </label>

                <p>
                  El backend impedirá cambiar el alcance
                  si el cupón ya fue utilizado.
                </p>

                <div className="admin-coupon-actions">
                  <button
                    type="submit"
                    disabled={saving}
                    className="operator-primary"
                  >
                    Guardar alcance
                  </button>

                  <button
                    type="button"
                    disabled={saving}
                    onClick={() => setScopeId(null)}
                  >
                    Cancelar
                  </button>
                </div>
              </form>
            )}
          </section>
        </div>
      </div>
    </main>
  );
}
