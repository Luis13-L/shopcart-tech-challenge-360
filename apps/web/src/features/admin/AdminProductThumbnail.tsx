import {
  useEffect,
  useState
} from "react";

import { Package } from "lucide-react";

import type {
  Product
} from "../../lib/catalog";

interface Props {
  product: Product;
}

export function AdminProductThumbnail({
  product
}: Props) {
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    setFailed(false);
  }, [product.imagenUrl]);

  if (!product.imagenUrl || failed) {
    return (
      <div className="admin-product-thumbnail fallback">
        <Package size={24} />
      </div>
    );
  }

  return (
    <img
      className="admin-product-thumbnail"
      src={product.imagenUrl}
      alt={
        product.imagenAlt ||
        product.nombreProducto
      }
      loading="lazy"
      onError={() => setFailed(true)}
    />
  );
}
