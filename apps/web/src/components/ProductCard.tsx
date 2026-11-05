import { useState } from "react";
import { ArrowUpRight, Box } from "lucide-react";

import {
  formatGTQ,
  type Product
} from "../lib/catalog";

// ==========================================
// CONTRATO DEL COMPONENTE
// ==========================================

interface ProductCardProps {
  product: Product;
  onPreview: (product: Product) => void;
}

// ==========================================
// TARJETA DE PRODUCTO
// ==========================================

export function ProductCard({
  product,
  onPreview
}: ProductCardProps) {

  const [imageFailed, setImageFailed] =
    useState(false);

  // Convencion temporal para imagenes.
  // Posteriormente utilizaremos URLImagen
  // proveniente de SQL Server.
  const imageUrl =
    `/images/products/${encodeURIComponent(product.sku)}.webp`;

  return (
    <article className="product-card">

      <div className="product-media">

        <span className="product-tag">
          {product.nombreCategoria}
        </span>

        {imageFailed ? (
          <div
            className="product-fallback"
            aria-label="Imagen no disponible"
          >
            <span className="product-orbit" />

            <Box
              size={65}
              strokeWidth={1.15}
              aria-hidden="true"
            />
          </div>
        ) : (
          <img
            src={imageUrl}
            alt={product.nombreProducto}
            loading="lazy"
            onError={() => setImageFailed(true)}
          />
        )}

      </div>

      <div className="product-content">

        <div className="product-meta">
          SKU · {product.sku}
        </div>

        <h3>{product.nombreProducto}</h3>

        <div className="product-bottom">

          <div>
            <strong className="product-price">
              {formatGTQ(product.precioActual)}
            </strong>

            <span className="product-stock">
              Existencia física: {product.cantidadFisica}
            </span>
          </div>

          <button
            className="icon-button product-open"
            type="button"
            aria-label={
              `Ver detalle de ${product.nombreProducto}`
            }
            onClick={() => onPreview(product)}
          >
            <ArrowUpRight size={19} />
          </button>

        </div>

      </div>

    </article>
  );
}
