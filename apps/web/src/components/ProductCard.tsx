import { useEffect, useState } from "react";

import {
  ArrowUpRight,
  Box,
  ShoppingBag
} from "lucide-react";

import {
  formatGTQ,
  type Product
} from "../lib/catalog";

interface ProductCardProps {
  product: Product;
  onPreview: (product: Product) => void;
  onAdd: (product: Product) => void;
  adding: boolean;
}

export function ProductCard({
  product,
  onPreview,
  onAdd,
  adding
}: ProductCardProps) {

  const [imageFailed, setImageFailed] =
    useState(false);

  const imageUrl = product.imagenUrl;

    useEffect(() => {
      setImageFailed(false);
    }, [imageUrl]);

  const soldOut =
    product.cantidadFisica <= 0;

  return (
    <article className="product-card">

      <div className="product-media">

        <span className="product-tag">
          {product.nombreCategoria}
        </span>

        {!imageUrl || imageFailed ? (

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
              alt={product.imagenAlt || product.nombreProducto}
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
              {soldOut
                ? "Sin existencia física"
                : `Existencia física: ${product.cantidadFisica}`}
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

        <button
          type="button"
          className="product-add-button"
          disabled={adding || soldOut}
          onClick={() => onAdd(product)}
        >
          <ShoppingBag size={17} />

          {soldOut
            ? "Agotado"
            : adding
              ? "Actualizando..."
              : "Añadir al carrito"}
        </button>

      </div>

    </article>
  );
}
