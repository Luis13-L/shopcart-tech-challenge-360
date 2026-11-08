import { unlink } from "node:fs/promises";

import type {
  CreateProductInput
} from "./catalog.create.schema.js";

import {
  storeProductImage
} from "./catalog.image.storage.js";

import {
  insertProductWithImage
} from "./catalog.image.repository.js";

export async function createProductWithImage(
  actorId: number,
  input: CreateProductInput,
  file: Express.Multer.File
) {
  const image = await storeProductImage(file);

  try {
    return await insertProductWithImage(
      actorId,
      input,
      image.url
    );

  } catch (error) {
    await unlink(image.filePath)
      .catch(() => undefined);

    throw error;
  }
}
