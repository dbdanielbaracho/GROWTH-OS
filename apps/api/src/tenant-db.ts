import type { PoolClient } from "pg";
import { db } from "./db.js";
import type { AuthPrincipal } from "./auth.js";

export async function withTenantTransaction<T>(
  principal: AuthPrincipal,
  work: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await db.connect();

  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [principal.workspaceId]);
    await client.query("SELECT set_config('app.user_id', $1, true)", [principal.userId]);

    const result = await work(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
