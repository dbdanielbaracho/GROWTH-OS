# Execution Log — Metric Quality Analytics Runtime Fix

Date: 2026-09-21
Status: CLOSED / PRODUCTION VERIFIED

## Incident

The production Analytics anomaly path failed at runtime because `growth.list_metric_quality_anomalies(...)` contained PL/pgSQL name ambiguity between output-column names and query/CTE identifiers. The previous gate inspected definition/permissions but did not execute the function body, so PostgreSQL deferred the runtime failure until the helper was called.

## Corrective release — PR #215

- PR: #215 — `Fix production metric-quality analytics runtime`
- PR tested head: `2253077c63f498c35d79eb46154dcfbec9e654b6`
- PR CI run: `35556981790` — SUCCESS
- Merge SHA: `ce07aa30927f8d7f8456760f35f5616ad7928c24`
- Migration: `db/migrations/074_metric_quality_anomalies_runtime_fix.sql`
- Regression gate changed from definition-only inspection to real execution of the metric-quality helper on PostgreSQL.
- Railway migrator deployment: `85955aba-ea5d-4afb-bf8a-b419520837d7` — SUCCESS
- Railway confirmed migration 074 applied and production migration reconciliation completed.
- Railway app deployment: `a605eae9-e9e7-4238-9e8e-d9d8b5433c7c` — SUCCESS
- App deployment identity matched merge SHA `ce07aa30927f8d7f8456760f35f5616ad7928c24`.
- `/health/ready` returned HTTP 200.

## Permanent Production Truth Gate — PR #216

- PR: #216 — `Add production smoke for metric-quality runtime`
- PR tested head: `bc6f771a01e46fcf21ae60f82f5535b5b453b19d`
- PR CI run: `35557836174` — SUCCESS
- Merge SHA: `e80e7e3665ed68941e11945e4183f7cd66904030`
- Main CI run: `35558221215` — SUCCESS
- New smoke script: `db/scripts/metric-quality-operational-smoke.mjs`
- Production reconciler now runs the metric-quality helper after migration reconciliation.
- Smoke chooses an active production membership, sets transaction-local `app.user_id` and `app.workspace_id`, executes `growth.list_metric_quality_anomalies(...)`, verifies a result count, and rolls back.
- The smoke is intentionally fail-closed: a PL/pgSQL runtime regression makes the migrator deployment fail.

## Exact production evidence for accepted runtime SHA

Accepted runtime SHA: `e80e7e3665ed68941e11945e4183f7cd66904030`

Railway migrator deployment:
- ID: `d688de35-da68-411b-8f3d-46bfb8fa11ca`
- Status: SUCCESS
- Database target: `railway`
- Runtime log: `Applied migration: /app/db/migrations/074_metric_quality_anomalies_runtime_fix.sql`
- Runtime log: `Production migration reconciliation complete`
- Runtime log: `Metric quality operational smoke target: { database: 'railway', user: 'postgres' }`
- Runtime log: `Production metric quality operational smoke: PASS helper executed; anomaly_count=0; rollback complete`

Railway application deployment:
- ID: `304196f1-1291-402c-b6cb-dd55ed05f30e`
- Status: SUCCESS
- Deployment identity: `e80e7e3665ed68941e11945e4183f7cd66904030`
- `/health/ready`: HTTP 200
- Post-deploy live traffic also returned HTTP 200 for authenticated session and provider-status/media routes.

## Closure

The original production runtime defect is corrected and the missing class of verification is now permanently represented by both an isolated-CI execution gate and a production transaction/rollback smoke. The incident is CLOSED. Any future failure of this helper at PL/pgSQL runtime is expected to stop the migrator deployment before the application release is accepted.

This closure does not redefine unrelated external/provider gates or claim that third-party provider availability is guaranteed; it closes only the metric-quality analytics runtime defect and its missing regression coverage.
