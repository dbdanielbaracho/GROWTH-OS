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


export type WorkerSystemContext = {
  servicePrincipalId: string;
};

export type WorkerTenantContext = WorkerSystemContext & {
  workspaceId: string;
  jobId: string;
};

async function beginWorkerTransaction(
  client: PoolClient,
  context: WorkerSystemContext,
  workspaceId: string | null,
  jobId: string | null
): Promise<void> {
  await client.query("BEGIN");
  await client.query("SELECT set_config('app.user_id', $1, true)", [""]);
  await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceId ?? ""]);
  await client.query("SELECT set_config('app.service_principal_id', $1, true)", [context.servicePrincipalId]);
  await client.query("SELECT set_config('app.job_id', $1, true)", [jobId ?? ""]);
}

export async function withWorkerSystemTransaction<T>(
  context: WorkerSystemContext,
  work: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await db.connect();

  try {
    await beginWorkerTransaction(client, context, null, null);
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

export async function withWorkerTenantTransaction<T>(
  context: WorkerTenantContext,
  work: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await db.connect();

  try {
    await beginWorkerTransaction(client, context, context.workspaceId, context.jobId);
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
