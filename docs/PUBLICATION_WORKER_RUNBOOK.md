# Publication worker operational contract

## Purpose

The publication worker consumes due publication jobs through the canonical queue helpers. It runs with a dedicated service principal and a dedicated PostgreSQL credential; it is not an anonymous background process and it never uses the API runtime credential as a fallback.

## Required configuration

Set these variables only in the worker process environment:

- `PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID`: UUID of an active row in `growth.worker_service_principals`.
- `PUBLICATION_WORKER_DATABASE_URL`: PostgreSQL URL for the canonical database, using the worker credential.
- `PUBLICATION_WORKER_INTERVAL_MS`: optional polling interval, clamped to 1–60 seconds; default 5 seconds.
- `PUBLICATION_WORKER_MAX_ATTEMPTS`: optional maximum queue claims before a retryable job is moved to `dead`; clamped to 1–20; default 5.

The process copies the validated worker URL into `DATABASE_URL` only after all checks pass. Do not commit or print any credential value.

## Process and evidence

Start with `npm run worker:publication`. Each tick claims at most one due job, executes the protected publication flow, and completes the job as `done`, `retry_wait`, or `dead`. A retryable provider result or worker exception returns to `retry_wait` while the claimed attempt count remains below `PUBLICATION_WORKER_MAX_ATTEMPTS`. Once the configured attempt limit is reached, the job transitions to terminal `dead` state and is no longer claimed automatically.

Structured logs contain only the event, worker result, queue state and opaque identifiers; provider tokens, request payloads and raw error text are excluded. A `queue_state` of `dead` is the operational evidence that automatic retries were exhausted and manual investigation/reconciliation is required.

A worker restart is safe: leases expire and the queue claim helper can recover due work. The provider result remains governed by the publication intent finalization, retry and reconciliation contracts.

## Deployment checklist

1. Provision the active service principal and worker credential in the canonical Railway environment.
2. Set the required variables above in the worker service; leave `PUBLICATION_WORKER_MAX_ATTEMPTS` unset to use the safe default unless operations explicitly chooses another bounded value.
3. Run the exact GitHub SHA through CI.
4. Confirm the worker starts without configuration errors.
5. Create a controlled approved publication intent in a non-production/pilot workspace.
6. Verify claim, provider result, final status and audit evidence.
7. Verify retry, dead-letter, cancellation and reconciliation behavior before enabling a real pilot.
8. Record the exact deployment, migration and live evidence in `docs/PROJECT_EXECUTION_MEMORY.md`.

The canonical Railway production environment is active. Promotion still requires the exact-SHA deployment gate and live evidence; no secret or provider credential is documented here.
