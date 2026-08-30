# RC8 six-failure regression contract

Execute on PostgreSQL 18.6 against a fresh canonical compile. Do not infer PASS.

## R1 — audit_events workspace FK
Insert a tenant audit event with a random non-existent `workspace_id`.
Expected: FK violation. A NULL `workspace_id` system event may remain valid under the system-role contract.

## R2 — tombstone read denial
Create a valid tenant/content item, then a valid deletion_request and an effective
`deletion_tombstones` row with `target_type='content'` and `target_id=<content_item_id>`.
As `app_runtime` with valid `app.user_id` + `app.workspace_id`, SELECT the content item and its versions.
Expected: zero rows from both normal tenant read paths after the tombstone is effective.

## R3 — deletion state machine
Create a deletion_request and exercise legal forward transitions.
Expected legal path: requested -> tombstoned -> purging -> provider_pending -> completed.
Then try `completed -> requested`.
Expected: error `completed deletion request is terminal`.
Also try invalid skips/backward moves; they must fail. `failed -> requested` is the explicit retry path.

## R4 — metric late arrival invalidates completeness
Create content + metric_completeness with `available=true`, a past `last_checked_at`, and then
insert a metric_observation for the same workspace/content/metric where `observed_at <= last_checked_at`
but the observation is inserted after that check.
Expected: completeness becomes `available=false` with
`reason_unavailable='late_arrival_requires_reconciliation'`.

## R5 — AI routing modality/policy compatibility
Create provider policy P for provider/model/region with modality `text`.
Try allowlist row referencing P but declaring modality `image`.
Expected: composite FK violation.
Then insert a fully matching row; expected success.

## R6 — pool partial-context safety
Create two tenants and active memberships. Establish valid context for tenant A and verify A data is visible.
Then clear/reset only `app.user_id` while intentionally leaving `app.workspace_id=A`.
Expected: ordinary tenant tables such as `managed_accounts` return zero rows.
Restore a valid A user and confirm A rows reappear.
Also verify a user active only in tenant B cannot read A merely by setting `app.workspace_id=A`.

## Mandatory regression preservation
After R1-R6 pass, rerun at minimum:
- membership takeover regression;
- tests/009 membership matrix unchanged;
- C1-C4 membership concurrency;
- publication lineage RC7 regressions;
- insight cycle RC7 regressions;
- experiment/exposure temporal RC7 regressions;
- tenant FK/RLS escape matrix;
- authority concurrency;
- confirmed_owned_only;
- deadlock_retry_safety.
