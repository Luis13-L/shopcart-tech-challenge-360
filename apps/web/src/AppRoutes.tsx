
import {
  Navigate,
  Route,
  Routes
} from "react-router";

import App from "./App";

import { LoginPage } from "./pages/LoginPage";
import { RegisterPage } from "./pages/RegisterPage";
import { WorkspacePage } from "./pages/WorkspacePage";

import { CartPage } from "./features/cart/CartPage";

import {
  CheckoutPage
} from "./features/checkout/CheckoutPage";

import {
  OrderSuccessPage
} from "./features/checkout/OrderSuccessPage";

import {
  OrdersPage
} from "./features/orders/OrdersPage";

import {
  OrderDetailPage
} from "./features/orders/OrderDetailPage";
import {
  OperatorOrdersPage
} from "./features/operations/OperatorOrdersPage";

import { RequireRole } from "./auth/RequireRole";

export default function AppRoutes() {
  return (
    <Routes>

      {/* RUTAS PUBLICAS */}

      <Route path="/" element={<App />} />

      <Route
        path="/login"
        element={<LoginPage />}
      />

      <Route
        path="/registro"
        element={<RegisterPage />}
      />

      {/* CLIENTE */}

      <Route
        element={
          <RequireRole allowed={["Cliente"]} />
        }
      >
        <Route
          path="/mi-cuenta"
          element={<WorkspacePage />}
        />

        <Route
          path="/carrito"
          element={<CartPage />}
        />

        <Route
          path="/checkout"
          element={<CheckoutPage />}
        />

        <Route
          path="/pedido-confirmado"
          element={<OrderSuccessPage />}
        />

        <Route
          path="/mis-pedidos"
          element={<OrdersPage />}
        />

        <Route
          path="/mis-pedidos/:id"
          element={<OrderDetailPage />}
        />
      </Route>

      {/* OPERADOR Y ADMINISTRADOR */}

      <Route
        element={
          <RequireRole
            allowed={[
              "Operador",
              "Administrador"
            ]}
          />
        }
      >
        <Route
          path="/operacion"
          element={<WorkspacePage />}
        />
        <Route
          path="/operacion/pedidos"
          element={<OperatorOrdersPage />}
        />
      </Route>

      {/* ADMINISTRADOR */}

      <Route
        element={
          <RequireRole
            allowed={["Administrador"]}
          />
        }
      >
        <Route
          path="/administracion"
          element={<WorkspacePage />}
        />
      </Route>

      {/* DESCONOCIDA */}

      <Route
        path="*"
        element={<Navigate to="/" replace />}
      />

    </Routes>
  );
}
