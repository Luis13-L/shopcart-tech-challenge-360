import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { BrowserRouter } from "react-router";

import {
  AuthProvider
} from "./auth/AuthProvider";

import {
  CartProvider
} from "./features/cart/CartProvider";

import AppRoutes from "./AppRoutes";

import "./index.css";
import "./styles/auth.css";
import "./styles/cart.css";
import "./styles/checkout.css";

const rootElement =
  document.getElementById("root");

if (!rootElement) {
  throw new Error(
    "No se encontro el elemento root"
  );
}

createRoot(rootElement).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <CartProvider>
          <AppRoutes />
        </CartProvider>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>
);
