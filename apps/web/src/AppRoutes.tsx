
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

import { RequireRole } from "./auth/RequireRole";

export default function AppRoutes() {
  return (
    <Routes>

      {/* RUTAS PUBLICAS */}

      <Route
        path="/"
        element={<App />}
      />

      <Route
        path="/login"
        element={<LoginPage />}
      />

      <Route
        path="/registro"
        element={<RegisterPage />}
      />

      {/* RUTAS DE CLIENTE */}

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
      </Route>

      {/* OPERADOR Y ADMINISTRADOR */}

      <Route
        element={
          <RequireRole
            allowed={["Operador", "Administrador"]}
          />
        }
      >
        <Route
          path="/operacion"
          element={<WorkspacePage />}
        />
      </Route>

      {/* ADMINISTRADOR */}

      <Route
        element={
          <RequireRole allowed={["Administrador"]} />
        }
      >
        <Route
          path="/administracion"
          element={<WorkspacePage />}
        />
      </Route>

      {/* RUTA DESCONOCIDA */}

      <Route
        path="*"
        element={<Navigate to="/" replace />}
      />

    </Routes>
  );
}
