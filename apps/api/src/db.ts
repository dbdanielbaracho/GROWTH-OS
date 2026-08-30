import pg from "pg";
import { env } from "./config.js";

const { Pool } = pg;

export const db = new Pool({
  connectionString: env.DATABASE_URL,
  max: 10,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000
});

export async function checkDatabase(): Promise<void> {
  await db.query("select 1 as ok");
}
