import {
  Navigate,
  Route,
  Routes
} from "react-router";

import App from "./App";

import {
  LoginPage
} from "./pages/LoginPage";

import {
  RegisterPage
} from "./pages/RegisterPage";

import {
  WorkspacePage
} from "./pages/WorkspacePage";

import {
  CartPage
} from "./features/cart/CartPage";

import {
  RequireRole
} from "./auth/RequireRole";

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

      {/* NO ENCONTRADA */}

      <Route
        path="*"
        element={<Navigate to="/" replace />}
      />

    </Routes>
  );
}
