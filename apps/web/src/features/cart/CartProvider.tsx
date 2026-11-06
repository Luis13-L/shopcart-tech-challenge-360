import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode
} from "react";

import { useAuth } from "../../auth/AuthProvider";

import {
  ensureCart,
  fetchCart,
  saveCartQuantity,
  deleteCartVariant,
  type Cart
} from "./cart.api";

type Feedback = {
  type: "success" | "error";
  message: string;
};

interface CartContextValue {
  cart: Cart | null;
  loading: boolean;
  busy: boolean;
  error: string | null;
  feedback: Feedback | null;
  itemCount: number;

  refresh: () => Promise<void>;
  addOne: (variantId: number) => Promise<void>;
  setQuantity: (
    variantId: number,
    quantity: number
  ) => Promise<void>;
  remove: (variantId: number) => Promise<void>;
  clearFeedback: () => void;
}

const CartContext =
  createContext<CartContextValue | null>(null);

function messageFrom(error: unknown): string {
  return error instanceof Error
    ? error.message
    : "Ocurrio un error al actualizar el carrito";
}

export function CartProvider({
  children
}: {
  children: ReactNode;
}) {

  const { session, ready } = useAuth();

  const ownerId =
    ready && session?.user.rol === "Cliente"
      ? session.user.id
      : null;

  // Asociar cada carrito a su propietario.
  const [snapshot, setSnapshot] = useState<{
    ownerId: number;
    cart: Cart;
  } | null>(null);

  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);

  const [error, setError] =
    useState<string | null>(null);

  const [feedback, setFeedback] =
    useState<Feedback | null>(null);

  // Evitar enviar cambios simultaneos que
  // utilicen cantidades desactualizadas.
  const mutationLocked = useRef(false);

  const cart =
    snapshot?.ownerId === ownerId
      ? snapshot.cart
      : null;

  // ========================================
  // CARGA INICIAL DEL CARRITO
  // ========================================

  useEffect(() => {

    let cancelled = false;

    if (ownerId === null) {
      setSnapshot(null);
      setError(null);
      setFeedback(null);
      setLoading(false);

      return;
    }

    setLoading(true);
    setError(null);
    setFeedback(null);

    async function load() {
      try {
        const id = await ensureCart();
        const data = await fetchCart(id);

        if (!cancelled && ownerId !== null) {
          setSnapshot({
            ownerId,
            cart: data
          });
        }
      } catch (cause) {
        if (!cancelled) {
          setError(messageFrom(cause));
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    void load();

    return () => {
      cancelled = true;
    };

  }, [ownerId]);

  // ========================================
  // RECARGAR DESDE SQL SERVER
  // ========================================

  async function refresh(): Promise<void> {

    if (ownerId === null || mutationLocked.current) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const id = await ensureCart();
      const data = await fetchCart(id);

      setSnapshot({
        ownerId,
        cart: data
      });
    } catch (cause) {
      setError(messageFrom(cause));
    } finally {
      setLoading(false);
    }
  }

  // ========================================
  // EJECUTAR UNA MUTACION
  // ========================================

  async function mutate(
    action: () => Promise<Cart>,
    successMessage: string
  ): Promise<void> {

    if (ownerId === null || mutationLocked.current) {
      return;
    }

    mutationLocked.current = true;
    setBusy(true);
    setFeedback(null);

    try {
      const updatedCart = await action();

      // Nunca calcular los totales localmente.
      // Utilizar la respuesta del backend.
      setSnapshot({
        ownerId,
        cart: updatedCart
      });

      setError(null);

      setFeedback({
        type: "success",
        message: successMessage
      });

    } catch (cause) {

      setFeedback({
        type: "error",
        message: messageFrom(cause)
      });

    } finally {
      mutationLocked.current = false;
      setBusy(false);
    }
  }

  // ========================================
  // AGREGAR UNA UNIDAD
  // ========================================

  async function addOne(
    variantId: number
  ): Promise<void> {

    if (!cart || loading) {
      setFeedback({
        type: "error",
        message: "El carrito aun no esta disponible"
      });
      return;
    }

    const existing = cart.items.find(
      item => item.idVariante === variantId
    );

    const newQuantity =
      (existing?.cantidad ?? 0) + 1;

    await mutate(
      () => saveCartQuantity(
        variantId,
        newQuantity
      ),
      "Producto agregado al carrito"
    );
  }

  // ========================================
  // CAMBIAR CANTIDAD ABSOLUTA
  // ========================================

  async function setQuantity(
    variantId: number,
    quantity: number
  ): Promise<void> {

    if (
      !Number.isSafeInteger(quantity) ||
      quantity < 0
    ) {
      setFeedback({
        type: "error",
        message: "Cantidad invalida"
      });
      return;
    }

    if (quantity === 0) {
      await remove(variantId);
      return;
    }

    await mutate(
      () => saveCartQuantity(
        variantId,
        quantity
      ),
      "Cantidad actualizada correctamente"
    );
  }

  // ========================================
  // ELIMINAR PRODUCTO
  // ========================================

  async function remove(
    variantId: number
  ): Promise<void> {

    await mutate(
      () => deleteCartVariant(variantId),
      "Producto eliminado del carrito"
    );
  }

  function clearFeedback(): void {
    setFeedback(null);
  }

  const itemCount = cart?.items.reduce(
    (total, item) => total + item.cantidad,
    0
  ) ?? 0;

  return (
    <CartContext.Provider
      value={{
        cart,
        loading,
        busy,
        error,
        feedback,
        itemCount,
        refresh,
        addOne,
        setQuantity,
        remove,
        clearFeedback
      }}
    >
      {children}
    </CartContext.Provider>
  );
}

// ==========================================
// CUSTOM HOOK
// ==========================================

export function useCart(): CartContextValue {

  const context = useContext(CartContext);

  if (!context) {
    throw new Error(
      "useCart debe utilizarse dentro de CartProvider"
    );
  }

  return context;
}
