import process from "node:process";
import { loadPublicationWorkerConfig } from "./publication-worker-config.js";

const workerConfig = loadPublicationWorkerConfig(process.env);

// The worker must use its dedicated database credential. It must never
// silently fall back to the API runtime credential.
process.env.DATABASE_URL = workerConfig.workerDatabaseUrl;

const { runPublicationQueueOnce } = await import("./publication-queue-worker.js");

let stopping = false;
let activeRun: Promise<void> | null = null;

async function tick(): Promise<void> {
  try {
    const result = await runPublicationQueueOnce({
      servicePrincipalId: workerConfig.servicePrincipalId,
      leaseSeconds: workerConfig.leaseSeconds
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
  if (!stopping) await new Promise((resolve) => setTimeout(resolve, workerConfig.intervalMs));
}
