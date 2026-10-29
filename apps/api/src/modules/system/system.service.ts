import { verifyDatabaseConnection } from "./system.repository.js";

export async function checkDatabaseHealth(): Promise<boolean> {
  return verifyDatabaseConnection();
}