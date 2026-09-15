# Current Project State

Last updated: 2026-09-15  
Purpose: single operational checkpoint for resuming Growth OS work without relying on chat memory.

## Repository

- Repository: `dbdanielbaracho/GROWTH-OS`.
- Current production-lineage `main` before this checkpoint update: `1ad55eb293fb19f6fa0107e6d39073950414c47d`.
- Historical stale PRs #29, #38, #49 and #65 were closed without merge after their valid work was proven already present or safely ported to current `main`.
- PR #154 merged bounded publication retries and terminal `dead` behavior.
- PR #155 merged the Instagram authorization timeout-state correction.
- PR #156 restored the design-quality benchmark v0.2.
- PR #157 refreshed the canonical project-state checkpoint.
- PR #158 merged safe publication queue-status projection and user-facing terminal dead-letter mapping.
- PR #163 merged migration 060 and the least-privilege runtime grants required by publication reconciliation.
- PR #164 added/fixed the production cancellation smoke and completed cancellation operational proof.
- PR #165 added public, non-secret deployment identity metadata.
- PR #166 made Railway deployment identity fail-closed in production.
- PR #167 committed `package-lock.json` and changed canonical CI dependency installation to `npm ci`.
- PR #168 temporarily pinned `npm@10.9.8`; the pin itself was valid, but combining Railpack Corepack packaging with a later custom `npm ci` install path exposed a Railpack 0.39 build failure.
- PR #169 removed the Corepack-triggering `packageManager` field while retaining lockfile-based deterministic `npm ci`; this is the current production build baseline.
- Detailed production-hardening execution log: `docs/EXECUTION_LOG_2026-09-15_PRODUCTION_HARDENING.md`.
- Roadmap current-status companion: `docs/ROADMAP_STATUS_RECONCILIATION_2026-09-15.md`. Historical prose in `docs/FULL_PRODUCT_ROADMAP.md` remains preserved for traceability.
- Important: changing this checkpoint creates a new head SHA. Always fetch the live `main`/PR head before exact-SHA decisions.

## Canonical production

- Railway project: `successful-embrace`.
- Environment: `production`.
- Canonical services: `growth-os`, `migrator`, Postgres and `growth-os-publication-worker`.
- Current production code lineage before this documentation update: `1ad55eb293fb19f6fa0107e6d39073950414c47d`.
- App deployment `8673eed4-e6f2-49f1-80c0-1e6459bb29f3`: `SUCCESS`.
- Migrator deployment `a6977b26-6079-4ee9-8f1a-5d760c94d087`: `SUCCESS`.
- Publication worker deployment `f308f3f1-0301-4859-91dc-34ca04a56917`: `SUCCESS`.
- Railway deployment metadata ties app deployment `8673eed4-e6f2-49f1-80c0-1e6459bb29f3` to exact commit `1ad55eb293fb19f6fa0107e6d39073950414c47d` on `main`.
- `/health/ready`: HTTP 200 on that app deployment.
- Production dependency installation is explicitly `npm ci --no-audit --no-fund` through `RAILPACK_INSTALL_CMD` on all three canonical application services.
- Railpack 0.39 still emits a cosmetic recommendation to declare a package-manager version when `packageManager` is absent. The explicit `packageManager` route is intentionally not used because, together with the custom install command, it caused the verified `/opt/corepack` packaging failure described below. The accepted operational contract is the committed lockfile + explicit `npm ci`.

## Canonical database state

Production migration reconciliation is confirmed through migration 060.

- Identity and provider foundations: 006, 009, 014–021.
- Publication contracts and operations: 022–032.
- Analytics, recommendation, experiment, automation and commercial controls: 033–039.
- Identity/runtime privilege corrections: 040–045.
- Managed-account/provider runtime corrections: 046–055.
- Publication worker principal/security reconciliation: 056–058.
- Safe publication queue-status projection: 059.
- Publication reconciliation runtime privileges: 060.

Migration 060 corrected the production reconciliation failure caused by insufficient table privileges while preserving the application/runtime least-privilege boundary. The current production migrator logs `Skipped migration (already present): 060_publication_reconciliation_runtime_privileges.sql` and `Production migration reconciliation complete`, proving the migration is present in the canonical database.

## Product capabilities already present in current main

- Authenticated identity/workspace foundation with tenant-scoped runtime controls.
- YouTube connection/sync product path, typed API contracts and versioned technical design.
- Instagram professional-account authorization, media/metrics sync and Growth Intelligence path.
- Opportunity Radar and editorial high-contrast design baseline.
- Content authoring, append-only versioning, review and approval controls.
- Publication intent, claim/finalization, assets, execution adapters, retry scheduling, cancellation and reconciliation.
- Dedicated publication worker service principal, runtime context, continuous worker process and Railway worker service.
- Bounded publication retries with terminal dead-letter state.
- Safe queue-status projection that maps terminal queue `dead` to user-facing `needs_user_action` without exposing internal job payload, lease or service-principal data.
- Production operational smoke coverage for queue/dead-letter, reconciliation and cancellation.
- Metric analytics summary, quality/anomaly contracts and authenticated analytics surface.
- Recommendation/feedback lineage, experiment lineage and controlled automation policy.
- Commercial entitlements / workspace governance foundation.
- Design-quality benchmark v0.2 with evidence boundaries and final/freeze acceptance gates.
- Public deployment metadata endpoint plus fail-closed Railway production identity invariant.
- Committed npm lockfile, canonical CI `npm ci`, and Railway `npm ci` install contract.

## Recent exact-SHA gates

### PR #158 — publication queue terminal status

- Exact candidate SHA: `17d604bf2a51ec342f4b12156d28d535c71e2015`.
- CI run: `34914145178` / #988.
- Full CI: success.
- Merge commit: `dacddf7bd4c0a99dc413a1b79e1e3c3f3edf00a6`.
- Production migration 059: applied successfully.

### PR #163 — reconciliation runtime privileges / migration 060

- Added migration `060_publication_reconciliation_runtime_privileges.sql` with only the privileges required by the production reconciliation path.
- CI applied migration 060 and passed the physical reconciliation gate.
- Production migrator applied/reconciled migration 060.
- The same reconciliation smoke that previously failed with `permission denied for table publication_intents` subsequently passed in production.

### PR #164 — cancellation operational proof

- Corrected the cancellation smoke fixture to respect the real actor/workspace trigger context instead of bypassing security.
- Exact-SHA CI: full success.
- Production smoke: `actor mismatch rejected; scheduled -> cancelled; cancelled/confirmed blocked; rollback complete`.
- Migrator now runs queue, reconciliation and cancellation smokes under one fail-fast (`set -e`) operational chain.

### PR #165 / #166 — deployment identity / fail-closed production lineage

- PR #165 exposed `/v1/deployment` with only non-secret deployment metadata (`commit_sha`, `deployment_id`, version/environment).
- PR #166 made Railway production startup fail if commit/deployment identity is absent.
- PR #166 exact candidate SHA `d0d6a404fa9d4112d8356e4f1f12cf91acf75fc7` passed every CI gate after correcting the new test setup.
- PR #166 merge commit: `67977bd6333c392ae0400f0205d09d805d05b13a`.
- Railway deployment `36d9c41f-b873-4f0e-8050-c60dce743808` logged verified identity for that exact SHA and passed `/health/ready` with HTTP 200.

### PR #167 — deterministic dependency lock

- Added canonical npm `package-lock.json` (lockfile v3), generated by the GitHub Actions Node 22/npm 10.9.8 environment rather than written by hand.
- Changed CI dependency installation from `npm install` to `npm ci`.
- Exact candidate SHA `e16b65a993b6ba76bb5b85cbd59da2af1ae74686` passed full CI run #1020.
- Merge commit: `bcb48210625ac514936b60b44bb9a4370fb9c306`.
- Production app/migrator/worker succeeded and health remained 200.

### PR #168 / #169 — Railpack package-manager hardening and recovery

- PR #168 pinned `npm@10.9.8`; its exact-SHA CI passed and the normal Railway build succeeded before the custom install override was enabled.
- After `RAILPACK_INSTALL_CMD=npm ci --no-audit --no-fund` was added to the three canonical services, Railpack 0.39 failed all three new builds at `copy /opt/corepack` with `lstat /opt/corepack: no such file or directory`.
- The failure was isolated to the Corepack packaging route, not to `npm ci`, TypeScript build, database migrations or application tests.
- PR #169 removed only the `packageManager` field, retained the existing `node >=22` contract aligned with the lockfile, and left explicit Railway `npm ci` enabled.
- PR #169 exact candidate SHA `4d7480a66de9a301cb636296c1790c86d7d09890` passed full CI run #1025.
- PR #169 merge commit/current code lineage: `1ad55eb293fb19f6fa0107e6d39073950414c47d`.
- Current production migrator build: `npm ci` confirmed, no `/opt/corepack` path, `SUCCESS`.
- Current publication worker build: `npm ci` confirmed, `SUCCESS`.
- Current app build: `npm ci` confirmed, `SUCCESS`.
- Current app deployment metadata: exact commit `1ad55eb293fb19f6fa0107e6d39073950414c47d`; health HTTP 200.

## Closed acceptance gaps in this hardening cycle

The following previously listed gaps are now closed by production evidence:

1. **Operational retry/dead-letter/reconciliation proof** — closed. Production queue smoke proves `queued -> leased(1) -> retry_wait -> leased(2) -> dead`; reconciliation smoke proves `ambiguous -> needs_user_action -> matched -> confirmed` with conflicting immutable replay rejected; all runs rollback their controlled fixtures.
2. **Cancellation operational proof** — closed. Production smoke verifies actor mismatch rejection, valid cancellation transition, terminal-state blocking and rollback.
3. **Technical production SHA/health traceability** — closed. Railway deployment metadata and the fail-closed runtime identity invariant prove the exact deployed code lineage, and health checks are 200.
4. **Deterministic dependency installation contract** — closed for CI and Railway canonical services through committed lockfile + explicit `npm ci`.

## Known truth / remaining acceptance gaps

The project is materially advanced but must not be declared fully complete yet. Remaining acceptance gaps are now narrower:

1. End-to-end authenticated browser validation of the main user journeys on the latest production lineage, including workspace/session, Instagram/YouTube integration states, CREATE/review/approval and publication operations.
2. Controlled real-provider publication evidence where provider configuration, permissions, account state and explicitly authorized content permit it. No claim of a real publish may be made without provider-side confirmation.
3. Final responsive/accessibility/cross-browser design evidence and same-task competitive comparison before visual freeze.
4. Final consolidated adversarial review only at the project/freeze gate, per current governance. Claude is not a required micro-gate for intermediate corrections and must not be claimed as completed without an actual Claude review.
5. Final Production Truth Gate on the final accepted SHA still needs its authenticated product/data portion: public URL/exact SHA and health are proven; frontend -> authenticated API -> real data -> expected result must still be captured on the final lineage.

## Next execution order

1. Keep `main` as the only technical baseline; do not revive stale feature branches.
2. Exercise authenticated end-to-end journeys on the latest production lineage and fix every reproducible runtime defect found.
3. Produce controlled real-provider publication evidence only with explicitly authorized content/account and provider-side confirmation.
4. Complete responsive/accessibility/cross-browser/competitive evidence.
5. Consolidate the final evidence package and run the final adversarial review.
6. Run the remaining authenticated/data portion of the final Production Truth Gate on one accepted SHA.
7. Only then mark the project frozen/complete.

## Operating rules

- Always verify the exact current SHA before CI, merge, deploy or acceptance claims.
- CI success is necessary but not sufficient for production acceptance.
- Railway production evidence must come from the canonical project/environment and exact deployment lineage.
- Never infer provider success from a local test, redirect or synthetic adapter response alone.
- Never use synthetic data as proof of a factual opportunity, provider result or production journey.
- Keep database/worker validation, application runtime validation and browser/provider validation as separate gates.
- A platform/tooling warning is not a product failure, but a tooling change that breaks canonical builds must be reverted/fixed before acceptance.
- Close or supersede stale branches rather than merging old history into current `main`.
- Record material execution, failures, fixes and acceptance evidence in GitHub so chat memory is not the source of truth.
