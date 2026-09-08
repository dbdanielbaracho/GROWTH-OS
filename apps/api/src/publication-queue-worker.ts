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
};

type QueueRunResult =
  | { status: "idle" }
  | {
      status: "processed" | "failed";
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

export async function runPublicationQueueOnce(input: {
  servicePrincipalId: string;
  leaseSeconds?: number;
  now?: Date;
}): Promise<QueueRunResult> {
  const now = input.now ?? new Date();
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
    const jobState = publicationStatus === "failed_retryable" || publicationStatus === "retrying"
      ? "retry_wait"
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
      jobId: job.id,
      publicationIntentId: intentId,
      publicationIntentStatus: publicationStatus
    };
  } catch (error) {
    await withWorkerTenantTransaction(context, async (client) => {
      await client.query(
        `select *
           from growth.complete_publication_job($1,$2,'retry_wait',$3,$4)`,
        [
          input.servicePrincipalId,
          job.id,
          new Date(now.getTime() + 60_000).toISOString(),
          safeErrorClass(error)
        ]
      );
    });

    return {
      status: "failed",
      jobId: job.id,
      publicationIntentId: intentId,
      publicationIntentStatus: null
    };
  }
}
