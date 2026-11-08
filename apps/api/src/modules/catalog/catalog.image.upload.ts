import multer from "multer";

import type {
  Request,
  Response,
  NextFunction
} from "express";

const allowedTypes = new Set([
  "image/jpeg",
  "image/png",
  "image/webp"
]);

const upload = multer({
  storage: multer.memoryStorage(),

  limits: {
    fileSize: 3 * 1024 * 1024,
    files: 1,
    fields: 5,
    parts: 6,
    fieldSize: 10000
  },

  fileFilter: (_req, file, callback) => {
    if (!allowedTypes.has(file.mimetype)) {
      callback(new Error(
        "Solo se permiten archivos JPG, PNG y WebP"
      ));
      return;
    }

    callback(null, true);
  }
}).single("imagen");

export function uploadProductImage(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  if (!req.is("multipart/form-data")) {
    res.status(415).json({
      code: "UNSUPPORTED_MEDIA_TYPE",
      message: "Se requiere multipart/form-data"
    });
    return;
  }

  upload(req, res, (error: unknown) => {
    if (!error) {
      next();
      return;
    }

    const tooLarge =
      error instanceof multer.MulterError &&
      error.code === "LIMIT_FILE_SIZE";

    res.status(tooLarge ? 413 : 400).json({
      code: "INVALID_IMAGE_UPLOAD",
      message: tooLarge
        ? "La imagen supera el máximo de 3 MB"
        : error instanceof Error
          ? error.message
          : "No se pudo recibir la imagen"
    });
  });
}
