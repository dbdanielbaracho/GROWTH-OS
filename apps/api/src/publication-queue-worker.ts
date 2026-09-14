import {
  withWorkerSystemTransaction,
  withWorkerTenantTransaction
} from "./tenant-db.js";
import {
  createWorkerDatabasePublicationExecutionStore
} from "./publication-store.js";
import {
  createPublicationProviderAdapter
} from "./publication-adapter-composition.js";
import { executePublicationIntent } from "./publication-worker.js";

type PublicationQueueJob = {
  id: string;
  workspace_id: string;
  service_principal_id: string;
  payload: unknown;
  state: "queued" | "leased" | "retry_wait" | "done" | "dead";
  attempts: number;
};

type PublicationQueueTerminalState = "retry_wait" | "done" | "dead";

type QueueRunResult =
  | { status: "idle" }
  | {
      status: "processed" | "failed";
      queueState: PublicationQueueTerminalState;
      jobId: string;
      publicationIntentId: string;
      publicationIntentStatus: string | null;
    };

function publicationIntentId(payload: unknown): string {
  if (
    !payload
    || typeof payload !== "object"
    || !("publication_intent_id" in payload)
    || typeof payload.publication_intent_id !== "string"
  ) {
    throw new Error("publication queue payload is invalid");
  }
  return payload.publication_intent_id;
}

function resultStatus(value: unknown): string | null {
  if (!value || typeof value !== "object" || !("status" in value)) return null;
  const status = value.status;
  return typeof status === "string" ? status : null;
}

function safeErrorClass(error: unknown): string {
  return error instanceof Error ? error.name : "unknown_worker_error";
}

function retryTerminalState(attempts: number, maxAttempts: number): "retry_wait" | "dead" {
  return attempts >= maxAttempts ? "dead" : "retry_wait";
}

export async function runPublicationQueueOnce(input: {
  servicePrincipalId: string;
  leaseSeconds?: number;
  maxAttempts?: number;
  now?: Date;
}): Promise<QueueRunResult> {
  const now = input.now ?? new Date();
  const maxAttempts = Math.max(1, input.maxAttempts ?? 5);
  const job = await withWorkerSystemTransaction(
    { servicePrincipalId: input.servicePrincipalId },
    async (client) => {
      const result = await client.query<PublicationQueueJob>(
        `select *
           from growth.claim_due_publication_job($1,$2,$3)
           limit 1`,
        [
          input.servicePrincipalId,
          now.toISOString(),
          input.leaseSeconds ?? 300
        ]
      );
      return result.rows[0] ?? null;
    }
  );

  if (!job) return { status: "idle" };

  const intentId = publicationIntentId(job.payload);
  const context = {
    servicePrincipalId: input.servicePrincipalId,
    workspaceId: job.workspace_id,
    jobId: job.id
  };

  try {
    const store = createWorkerDatabasePublicationExecutionStore(context, intentId);
    const publicationResult = await executePublicationIntent({
      store,
      adapterFactory: (claimed) => createPublicationProviderAdapter(claimed)
    });
    const publicationStatus = resultStatus(publicationResult);
    const isRetryable = publicationStatus === "failed_retryable" || publicationStatus === "retrying";
    const jobState: PublicationQueueTerminalState = isRetryable
      ? retryTerminalState(job.attempts, maxAttempts)
      : "done";

    await withWorkerTenantTransaction(context, async (client) => {
      await client.query(
        `select *
           from growth.complete_publication_job($1,$2,$3,$4,$5)`,
        [
          input.servicePrincipalId,
          job.id,
          jobState,
          jobState === "retry_wait"
            ? new Date(now.getTime() + 60_000).toISOString()
            : null,
          jobState === "done" ? null : publicationStatus ?? "publication_execution_failed"
        ]
      );
    });

    return {
      status: "processed",
      queueState: jobState,
      jobId: job.id,
      publicationIntentId: intentId,
      publicationIntentStatus: publicationStatus
    };
  } catch (error) {
    const jobState = retryTerminalState(job.attempts, maxAttempts);
    await withWorkerTenantTransaction(context, async (client) => {
      await client.query(
        `select *
           from growth.complete_publication_job($1,$2,$3,$4,$5)`,
        [
          input.servicePrincipalId,
          job.id,
          jobState,
          jobState === "retry_wait"
            ? new Date(now.getTime() + 60_000).toISOString()
            : null,
          safeErrorClass(error)
        ]
      );
    });

    return {
      status: "failed",
      queueState: jobState,
      jobId: job.id,
      publicationIntentId: intentId,
      publicationIntentStatus: null
    };
  }
}
