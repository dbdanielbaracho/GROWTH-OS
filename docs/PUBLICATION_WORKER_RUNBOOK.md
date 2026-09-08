# Publication worker operational contract

## Purpose

The publication worker consumes due publication jobs through the canonical queue helpers. It runs with a dedicated service principal and a dedicated PostgreSQL credential; it is not an anonymous background process and it never uses the API runtime credential as a fallback.

## Required configuration

Set these variables only in the worker process environment:

- `PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID`: UUID of an active row in `growth.worker_service_principals`.
- `PUBLICATION_WORKER_DATABASE_URL`: PostgreSQL URL for the canonical database, using the worker credential.
- `PUBLICATION_WORKER_INTERVAL_MS`: optional polling interval, clamped to 1–60 seconds; default 5 seconds.

The process copies the validated worker URL into `DATABASE_URL` only after all checks pass. Do not commit or print any value.

## Process and evidence

Start with `npm run worker:publication`. Each tick claims at most one due job, executes the protected publication flow, and completes the job as `done`, `retry_wait`, or `dead`. Structured logs contain only the event, status and opaque identifiers; provider tokens, payloads and error text are excluded.

A worker restart is safe: leases expire and the queue claim helper can recover due work. The provider result remains governed by the publication intent finalization, retry and reconciliation contracts.

## Deployment checklist

1. Provision the active service principal and worker credential in the canonical Railway environment.
2. Set the three variables above in the worker service only.
3. Run the exact GitHub SHA through CI.
4. Confirm the worker starts without configuration errors.
5. Create a controlled approved publication intent in a non-production/pilot workspace.
6. Verify claim, provider result, final status and audit evidence.
7. Verify retry and cancellation behavior before enabling a real pilot.
8. Record the exact deployment, migration and live evidence in `docs/PROJECT_EXECUTION_MEMORY.md`.

Production deployment and migration verification remain blocked until the canonical Railway account grants the required viewer/member role. No secret or provider credential is documented here.
