import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router";

import { AuthProvider } from "./auth/AuthProvider";
import AppRoutes from "./AppRoutes";

// Estilos globales de ShopCart
import "./index.css";

// Estilos del login y espacios autenticados
import "./styles/auth.css";

const rootElement = document.getElementById("root");

if (!rootElement) {
  throw new Error(
    "No se encontro el elemento root"
  );
}

createRoot(rootElement).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <AppRoutes />
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>
);
