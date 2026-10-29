
import sql from "mssql";
import { env } from "./env.js";

const config: sql.config = {
  user: env.SQL_USER,
  password: env.SQL_PASSWORD,
  server: env.SQL_SERVER,
  port: env.SQL_PORT,
  database: env.SQL_DATABASE,

  options: {
    encrypt: true,
    trustServerCertificate:
      env.NODE_ENV === "development"
  },

  pool: {
    max: 5,
    min: 0,
    idleTimeoutMillis: 30000
  },

  connectionTimeout: 15000,
  requestTimeout: 15000
};

let poolPromise:
  Promise<sql.ConnectionPool> | undefined;

export function getDbPool():
  Promise<sql.ConnectionPool> {

  if (!poolPromise) {
    const pool = new sql.ConnectionPool(config);

    poolPromise = pool.connect().catch(error => {
      poolPromise = undefined;
      throw error;
    });
  }

  return poolPromise;
}
