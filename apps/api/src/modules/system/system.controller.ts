import type { Request, Response } from "express";
import { checkDatabaseHealth } from "./system.service.js";

export async function getDatabaseHealth(
  _req: Request,
  res: Response
): Promise<void> {
  try {
    const connected = await checkDatabaseHealth();

    res.status(connected ? 200 : 503).json(
      connected
        ? { status: "ok", database: "connected" }
        : { status: "error", code: "DATABASE_UNAVAILABLE" }
    );
  } catch (error) {
    console.error("Error de conexion SQL:", error);

    res.status(503).json({
      status: "error",
      code: "DATABASE_UNAVAILABLE"
    });
  }
}