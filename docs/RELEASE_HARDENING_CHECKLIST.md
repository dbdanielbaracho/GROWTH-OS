# Growth OS — release hardening and Railway runbook

This document is the release gate for the complete material cycle. It is evidence-based and must be executed against the exact GitHub SHA being promoted.

## Before Claude review

1. Confirm the PR head SHA is the exact candidate SHA and GitHub CI is green.
2. Confirm all migrations and gates are present through the current release ceiling (migration/gate 072 for the active candidate).
3. Confirm no synthetic opportunity, observation, recommendation, experiment outcome or automation request is used as production proof.
4. Confirm automation requests are evidence-bound, pending by default, quota-limited and kill-switchable.
5. Confirm commercial state is internal/auditable and no external charge is implied without a configured billing provider.
6. Confirm Railway production still points at GitHub main and that no local branch is used as a promotion source.

## Railway production promotion after APPROVE only

1. Merge the reviewed PR into GitHub main.
2. Confirm the canonical migrator reconciles the complete ordered migration registry through the candidate ceiling; do not maintain a hand-written partial range.
3. Redeploy the migrator from the GitHub main source and wait for SUCCESS.
4. Confirm the app service still uses the GitHub main source, then redeploy the app from main.
5. Verify `/health/live`, `/health/ready` and `/v1/deployment`.
6. Verify the real deployment SHA in Railway metadata and record it in the execution memory.
7. Run the tenant-isolation, approval, quota, kill-switch and entitlement checks against production.
8. If any migration or health gate fails, stop promotion and restore service availability before retrying.

## Operational recovery

- Kill switch: set the workspace automation policy to kill_switch=true before investigating an automation incident.
- Provider safety: an approved request is still only an auditable request; provider execution requires a separately reviewed worker contract.
- Data safety: retain production backups and perform a restore drill before declaring Phase 11 Frozen.
- Commercial safety: do not mark a subscription active unless its provider reference and internal audit record are both present.
- Privacy: deletion and retention changes require an owner/admin actor and an audit record.

## Phase 11 service-level objectives

These objectives are evaluated by normalized route templates. Operational logs must never include session cookies, authorization headers, CSRF tokens, passwords, provider tokens, OAuth codes, raw provider payloads or tenant identifiers.

| Signal | Objective | Alert condition | Immediate response |
| --- | --- | --- | --- |
| Liveness | 99.95% successful responses over 30 days | two consecutive failed probes or five failures in five minutes | confirm process/deploy state; rollback the latest runtime-affecting release if the failure follows promotion |
| Readiness | 99.9% successful responses over 30 days | two consecutive 503 responses or database-unavailable state for two minutes | stop writes/provider execution, inspect database connectivity and preserve the last known-good deployment |
| Tenant API reads | p95 below 500 ms over 15 minutes | p95 above 750 ms for 15 minutes | inspect CPU/memory/database saturation and slow route class before scaling or changing queries |
| Tenant API writes | p95 below 1,000 ms over 15 minutes | p95 above 1,500 ms for 15 minutes | enable the relevant kill switch where applicable; do not retry ambiguous provider writes blindly |
| Server errors | below 1% over 15 minutes, excluding readiness probes during a declared incident | 5xx ratio at or above 2% for five minutes | classify by normalized route and deployment SHA; contain provider/automation impact first |
| Provider operations | no unclassified failure and no duplicate confirmed publication | any ambiguous publication or authorization failure lacking a recovery class | pause execution, reconcile provider state and require user action when certainty is unavailable |

The application emits `operational_request` records containing only method, normalized route template, status code, duration and SLO class. Railway deployment identity, HTTP logs and resource metrics remain the production evidence sources. Alert delivery configuration is a platform operation and must be evidenced separately; this table is not proof that a provider-side alert has fired.

## Phase 11 executable acceptance

The canonical CI must execute both gates after all migrations and test fixtures are present:

1. `phase11-runtime-acceptance.integration.mts` sends bounded concurrent bursts to liveness, database readiness and an unauthenticated tenant route. It requires exact expected status codes and p95 budgets; a 401 fail-closed response is the expected tenant-isolation result.
2. `phase11-restore-drill.mjs` creates a controlled content row, takes a real PostgreSQL custom-format backup, records a deletion/tombstone after the snapshot, restores into a separately named disposable quarantine database, proves the row is initially visible there, replays the deletion ledger, and proves the normal tenant read path denies the restored row. The target name, cluster, acknowledgement and source/target separation are validated before any database creation or removal.

The CI restore drill is repeatable recovery evidence for schema, ownership, grants, RLS and tombstone replay. It does not by itself prove Railway's production backup-retention setting or authorize restoring production data outside an approved quarantine environment.

## Security and privacy acceptance

- Authentication, CSRF origin checks, RBAC, FORCE RLS, helper ownership and least-privilege gates remain mandatory.
- Operational telemetry is payload-free and uses route templates, so UUIDs, query strings and tenant-specific paths are not recorded by the new event.
- Agency access requires current owner/admin rights in both linked workspaces.
- Consent decisions are append-only and retain the policy version.
- Deletion remains request -> tombstone -> purge evidence; tombstoning never claims provider/system purge completion.
- Restore eligibility requires deletion-ledger replay before serving traffic.
- Real provider OAuth and publication remain human/external authorization gates and cannot be replaced by fixtures or database mutation.
- Final adversarial review must inspect the exact accepted SHA after every material finding is fixed and affected gates are rerun.

## Freeze evidence

The project is complete only when the exact final SHA has green CI, Claude has returned APPROVE, Railway has promoted from GitHub main with SUCCESS deployments, production-truth checks pass, recovery evidence is recorded, and the release freeze is documented.
