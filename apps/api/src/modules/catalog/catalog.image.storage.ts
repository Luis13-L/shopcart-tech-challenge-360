import { randomUUID } from "node:crypto";
import {
  mkdir,
  unlink,
  writeFile
} from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

export const productImagesDir = fileURLToPath(
  new URL("../../../uploads/products/", import.meta.url)
);

export class InvalidProductImageError extends Error {}

export interface StoredProductImage {
  filePath: string;
  url: string;
}

export async function storeProductImage(
  file: Express.Multer.File
): Promise<StoredProductImage> {
  const expectedFormat: Record<string, string> = {
    "image/jpeg": "jpeg",
    "image/png": "png",
    "image/webp": "webp"
  };

  if (
    !expectedFormat[file.mimetype] ||
    file.size > 3 * 1024 * 1024
  ) {
    throw new InvalidProductImageError(
      "Solo se permiten imágenes JPG, PNG o WebP de hasta 3 MB."
    );
  }

  let webp: Buffer;

  try {
    const metadata = await sharp(file.buffer, {
      limitInputPixels: 16_000_000
    }).metadata();

    if (
      metadata.format !== expectedFormat[file.mimetype] ||
      !metadata.width ||
      !metadata.height
    ) {
      throw new Error("Formato inválido");
    }

    webp = await sharp(file.buffer, {
      limitInputPixels: 16_000_000
    })
      .rotate()
      .resize({
        width: 1200,
        height: 1200,
        fit: "inside",
        withoutEnlargement: true
      })
      .webp({ quality: 82 })
      .toBuffer();

  } catch {
    throw new InvalidProductImageError(
      "El archivo no contiene una imagen válida o segura."
    );
  }

  const filename = `${randomUUID()}.webp`;
  const filePath = join(productImagesDir, filename);

  await mkdir(productImagesDir, {
    recursive: true
  });

  try {
    await writeFile(filePath, webp, {
      flag: "wx"
    });
  } catch (error) {
    await unlink(filePath).catch(() => undefined);
    throw error;
  }

  return {
    filePath,
    url: `/api/images/products/${filename}`
  };
}
