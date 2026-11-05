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
  WorkspacePage
} from "./pages/WorkspacePage";

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

      {/* SOLO ADMINISTRADOR */}

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

      {/* RUTAS NO ENCONTRADAS */}

      <Route
        path="*"
        element={<Navigate to="/" replace />}
      />

    </Routes>
  );
}
