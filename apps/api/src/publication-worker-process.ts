import process from "node:process";

const configuredServicePrincipalId = process.env.PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID;
const configuredWorkerDatabaseUrl = process.env.PUBLICATION_WORKER_DATABASE_URL;
const intervalMs = Math.max(
  1_000,
  Math.min(60_000, Number.parseInt(process.env.PUBLICATION_WORKER_INTERVAL_MS ?? "5000", 10) || 5_000)
);

if (typeof configuredServicePrincipalId !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(configuredServicePrincipalId)) {
  console.error("publication worker requires PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID");
  process.exit(2);
}

if (typeof configuredWorkerDatabaseUrl !== "string" || configuredWorkerDatabaseUrl.length === 0) {
  console.error("publication worker requires PUBLICATION_WORKER_DATABASE_URL");
  process.exit(2);
}

// The worker must use its dedicated database credential. It must never
// silently fall back to the API runtime credential.
const servicePrincipalId = configuredServicePrincipalId;
const workerDatabaseUrl = configuredWorkerDatabaseUrl;
process.env.DATABASE_URL = workerDatabaseUrl;

const { runPublicationQueueOnce } = await import("./publication-queue-worker.js");

let stopping = false;
let activeRun: Promise<void> | null = null;

async function tick(): Promise<void> {
  try {
    const result = await runPublicationQueueOnce({
      servicePrincipalId,
      leaseSeconds: Math.min(900, Math.max(30, Math.ceil(intervalMs / 1000) * 3))
    });
    if (result.status !== "idle") {
      console.log(JSON.stringify({
        event: "publication_worker_job",
        status: result.status,
        job_id: result.jobId,
        publication_intent_id: result.publicationIntentId,
        publication_intent_status: result.publicationIntentStatus
      }));
    }
  } catch (error) {
    console.error(JSON.stringify({
      event: "publication_worker_error",
      error_class: error instanceof Error ? error.name : "unknown_worker_error"
    }));
  }
}

function stop(): void {
  stopping = true;
  if (!activeRun) process.exitCode = 0;
}

process.once("SIGTERM", stop);
process.once("SIGINT", stop);

while (!stopping) {
  activeRun = tick();
  await activeRun;
  activeRun = null;
  if (!stopping) await new Promise((resolve) => setTimeout(resolve, intervalMs));
}
