import type { PoolClient } from "pg";
import { db } from "./db.js";
import type { AuthPrincipal } from "./auth.js";

async function beginScopedTransaction(
  client: PoolClient,
  userId: string,
  workspaceId: string | null
): Promise<void> {
  await client.query("BEGIN");
  await client.query("SELECT set_config('app.user_id', $1, true)", [userId]);
  await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceId ?? ""]);
}

export async function withUserTransaction<T>(
  userId: string,
  work: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await db.connect();

  try {
    await beginScopedTransaction(client, userId, null);
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

export async function withTenantTransaction<T>(
  principal: AuthPrincipal,
  work: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await db.connect();

  try {
    await beginScopedTransaction(client, principal.userId, principal.workspaceId);
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
