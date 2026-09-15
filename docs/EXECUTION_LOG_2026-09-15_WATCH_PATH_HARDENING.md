# Growth OS — Railway Watch Path Hardening

Date: 2026-09-15

Purpose: prevent documentation-only repository changes from triggering unnecessary Railway production builds while preserving automatic deployment for code, database and dependency changes that materially affect each canonical service.

## Trigger for this hardening

PR #170 was documentation-only, but its merge commit `b9b16be8717b9f17cc6f92fa601056e1fee69cc2` still triggered new production builds for `growth-os` and `migrator`. That proved those services did not yet have restrictive Watch Paths.

The resulting deployment was healthy:

- `growth-os` deployment `72b6de52-9f4c-40d0-b30f-9dff74108523`: SUCCESS;
- app startup verified exact Railway commit `b9b16be8717b9f17cc6f92fa601056e1fee69cc2` and deployment ID;
- `/health/ready`: HTTP 200;
- `migrator` deployment `e910d6c2-7732-4623-84a6-9d74997ef026`: SUCCESS;
- migration reconciliation complete through migration 060;
- publication queue/dead-letter smoke: PASS;
- publication reconciliation smoke: PASS;
- publication cancellation smoke: PASS;
- publication worker did not redeploy from PR #170 because it already had Watch Paths that excluded documentation.

## Railway configuration changes

The following Watch Paths were applied directly to the canonical production service configuration.

### growth-os

- `/apps/**`
- `/packages/**`
- `/db/**`
- `/package.json`
- `/package-lock.json`

Rationale: the production app serves both API and built web assets, consumes shared packages and database contracts, and must redeploy for root dependency manifest/lockfile changes. Changes under documentation alone should not rebuild it.

### migrator

- `/db/**`
- `/packages/**`
- `/package.json`
- `/package-lock.json`
- `/apps/api/package.json`
- `/apps/web/package.json`

Rationale: the migrator must react to migrations/scripts and dependency/workspace-manifest changes, but ordinary application source or documentation changes do not require a migration run.

### growth-os-publication-worker

Existing Watch Paths were retained and `package-lock.json` was added:

- `/apps/api/**`
- `/packages/**`
- `/db/**`
- `/package.json`
- `/package-lock.json`

Rationale: the worker runs from API code, depends on shared/database contracts and must rebuild on dependency lockfile changes. Documentation-only changes must not redeploy it.

## Safety boundary

This optimization does not change runtime code, database privileges, provider credentials, worker behavior, health checks, retry policy or publication semantics. It changes only which repository paths are allowed to trigger automatic Railway builds.

Database paths remain included for `growth-os` and publication worker intentionally, so schema/privilege contract changes continue to produce same-lineage runtime deployments where appropriate.

## Acceptance test

This document itself is the first documentation-only acceptance test after Watch Paths were applied.

Acceptance condition after merge:

1. merge is successful on `main`;
2. no new deployment ID appears for `growth-os`;
3. no new deployment ID appears for `migrator`;
4. no new deployment ID appears for `growth-os-publication-worker`;
5. the existing serving `growth-os` deployment remains healthy.

Post-merge deployment IDs will be compared against this pre-merge baseline:

- app: `72b6de52-9f4c-40d0-b30f-9dff74108523`;
- migrator: `e910d6c2-7732-4623-84a6-9d74997ef026`;
- publication worker: `f308f3f1-0301-4859-91dc-34ca04a56917`.

If all three IDs remain unchanged after this documentation-only merge, the Watch Path hardening is physically proven in production configuration rather than merely inferred from settings.
