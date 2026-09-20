# Growth OS — Roadmap Status Reconciliation

Date: 2026-09-15  
Accepted runtime SHA before this documentation-only update: `f1b3009e126faf6d388b1e5dca7e681c8e991ac6`  
Purpose: current-status companion to `docs/FULL_PRODUCT_ROADMAP.md`.

## Current addendum — 2026-09-18

The 2026-09-15 checkpoint below remains historical evidence. Current accepted application runtime is PR #194 merge `a11f9bce3c5675263545b2e5e3ebb42b421cef21`, deployment `20e86731-0350-4675-ab20-c6032a8b34a7`; repository head after documentation-only PR #195 is `bbc1d4b84b85734eebb40e4088a49e26662da72b`. Production migrations are reconciled through 065, not 060.

Authenticated production revalidation on 2026-09-18 confirmed real Instagram opportunity/evidence/intelligence and eight media / sixteen metrics, but exposed two open live regressions: experiment listing fails with SQLSTATE `42501` because the SECURITY DEFINER owner lacks base experiment-table privileges, and a fresh YouTube seven-day sync returns HTTP 502. Migration 066 / SQL gate 068 and safe YouTube connector-code logging are the active correction. The first gate execution also found the existing ambiguous `status` predicate in `add_experiment_variant`; forward-only migration 067 qualifies it before production. No real external publication is claimed.

## Current addendum — 2026-09-20

PR #204 closed the Creative Studio and publication-calendar product-surface gaps. PR #205 closed the distinct evidence-bounded Global Trend Migration, Competitor Intelligence and Viral DNA module gap. Accepted runtime/repository SHA is `f3710e66dc772bf07915ebdbbe1bb938c6910f82`; PR CI #1350 and merged-main CI #1351 succeeded. Railway app, migrator and publication worker deployments succeeded, and migration 071 was applied by the canonical migrator.

PR #206 closed the adopted Phase 10 operational gap with migration/gate 072. Agency links require administration in both workspaces; support cases are audited; consent is append-only; deletion remains request -> tombstone -> separately evidenced purge. CI #1353/#1354 passed and Railway promoted exact SHA `f7b11bdfaeaf8365618e6eb4ed4ce2ae2a599775`, including migration 072. External billing remains out of adopted scope.

The active internal candidate is `feat/phase11-hardening`: bounded load/resilience, payload-free operational telemetry, SLO/alert rules and a PostgreSQL quarantine restore drill that replays deletion tombstones before serving restored data.

## Authority and history

`docs/FULL_PRODUCT_ROADMAP.md` is an execution roadmap with chronological addenda. Older statements such as “future phase”, “pending Railway”, or early migration ceilings describe the state at the time they were written and must not be read as the current production truth.

For current execution status, use this document together with `PROJECT_CURRENT_STATE.md`. Historical roadmap text remains preserved for traceability rather than being silently rewritten.

Detailed evidence for the latest cycles is recorded in:

- `docs/EXECUTION_LOG_2026-09-15_PRODUCTION_HARDENING.md`;
- `docs/EXECUTION_LOG_2026-09-15_WATCH_PATH_HARDENING.md`;
- `docs/EXECUTION_LOG_2026-09-15_BROWSER_QUALITY_GATE.md`.

## Production truth at this checkpoint

Canonical Railway project: `successful-embrace`, environment `production`.

Canonical runtime services are `growth-os`, `migrator`, Postgres and `growth-os-publication-worker`.

Accepted production code lineage:

`f1b3009e126faf6d388b1e5dca7e681c8e991ac6`

Production evidence for that lineage:

- merged-main GitHub CI run `34979049457`: SUCCESS;
- app deployment `57cb874b-2dc9-4055-b64b-b5da38138a5e`: SUCCESS;
- Railway app deployment identity identifies exact commit `f1b3009e126faf6d388b1e5dca7e681c8e991ac6` and that deployment ID;
- Railway `/health/ready` probe: HTTP 200;
- custom host `growos.predibeacon.com` is receiving production ingress;
- migrator deployment `1c80b068-cb44-4b65-9e13-b64538c61211`: SUCCESS on the same SHA;
- publication worker deployment `f308f3f1-0301-4859-91dc-34ca04a56917`: SUCCESS and intentionally unchanged by the web-only PR #173 change;
- migrations reconciled through 060;
- production queue/dead-letter smoke: PASS;
- production reconciliation smoke: PASS;
- production cancellation smoke: PASS;
- canonical CI installs dependencies with `npm ci` from committed `package-lock.json`;
- canonical Railway app/migrator/worker builds use `npm ci --no-audit --no-fund` through `RAILPACK_INSTALL_CMD`;
- canonical CI now includes Playwright/axe browser-quality validation across Chromium, Firefox and WebKit, desktop/mobile, keyboard traversal, horizontal overflow, and serious/critical WCAG findings.

The production database is reconciled through migration 060. Earlier roadmap notes that describe production as pending migrations in the 030–033 or 059 range are superseded.

## Phase-by-phase reconciliation

| Phase | Current classification | Current truth | Remaining acceptance work |
| --- | --- | --- | --- |
| 0 — Program control and platform contracts | In progress / mature foundation | Canonical docs, exact-SHA CI, migration reconciliation, production lineage identity, fail-closed deployment identity, deterministic dependency installation and Watch Path governance are operating. | Final freeze package, consolidated evidence index and final acceptance record. |
| 1 — Identity, tenancy and access | Implemented foundation; not Frozen | Authenticated identity/workspace foundation, tenant-scoped runtime controls, sessions/invitations and production identity migrations are present. Signed-out identity browser behavior now has automated multi-browser/axe coverage. | Final authenticated production browser proof for complete account/workspace/recovery/admin journeys and final security acceptance. |
| 2 — Application shell and design system | Automated browser gate closed; final visual acceptance open | Production web shell and editorial high-contrast baseline exist; design-quality benchmark v0.2 is versioned. PR #173 adds canonical Chromium/Firefox/WebKit, desktop/mobile, keyboard, overflow and serious/critical axe gating and corrected real accessibility defects found by that gate. | Authenticated production recovery-state/browser proof, same-task competitive visual comparison and final visual freeze. |
| 3 — Channel connectors | In progress | Instagram professional authorization/media/metrics/Growth Intelligence path and YouTube connection/sync product path are implemented. | Complete real-provider acceptance, including provider verification/permissions, reconnect/recovery and supported real-account proofs. |
| 4 — Content operations | In progress / core implemented | Content authoring, append-only versioning, review and approval controls are present; Creative Production foundations also exist. | Full authenticated production end-to-end content journey evidence, remaining product-surface completeness and final freeze. |
| 5 — Publishing and orchestration | In progress / technical stack production-deployed | Publication intent, execution adapters, retries, cancellation, reconciliation, worker service principal, bounded retry/dead-letter and safe queue-status projection are deployed. Production smokes prove queue/dead-letter, reconciliation and cancellation behavior. | Controlled real-provider publication evidence and authenticated production end-to-end publication journey. |
| 6 — Data and analytics | In progress | Metrics foundations, analytics summary, quality/anomaly contracts and authenticated analytics surface are present. | Final dashboard/export/freshness/completeness acceptance and real-data traceability proof across supported providers. |
| 7 — Intelligence platform | In progress | Growth Intelligence, Opportunity Radar and evidence-aware intelligence foundations are implemented. Controlled Radar UI behavior now participates in the canonical cross-browser gate. | Complete remaining intelligence modules only where provider/data access permits, plus measurable production evaluation and final evidence boundaries. |
| 8 — Experiments and multiplication | In progress | Experiment lineage and controlled experiment foundations exist. | End-to-end experiment creation, publication, measurement and winner/loser lifecycle evidence. |
| 9 — Copilot, Autopilot and operations | In progress / policy foundation | Controlled automation policy, bounded actions, publication worker and operational smoke foundations exist. Automation selector accessibility is now protected by the browser-quality gate. | Complete user-facing Copilot/Autopilot journeys, operational alerts/incidents and final safety/recovery acceptance. |
| 10 — Commercial and enterprise platform | In progress / entitlement foundation | Commercial entitlements and workspace-governance foundations exist. | Real billing-provider integration if adopted, full agency/enterprise administration, compliance/support tooling and commercial acceptance. |
| 11 — Production hardening and launch | Active / narrowed external critical path | Exact-SHA CI, Railway deployment validation, deployment identity, health checks, migrations through 060, fail-fast publication smokes, lockfile/`npm ci`, Watch Paths and automated browser/responsive/accessibility/cross-browser gates are operating. | Authenticated production E2E, controlled real-provider publication, same-task competitive/final visual acceptance, final adversarial review and remaining authenticated/data portion of the Production Truth Gate. |

## Browser-quality acceptance now closed

PR #173 established a canonical automated gate rather than a one-off manual check.

Coverage includes:

- Chromium, Firefox and WebKit;
- desktop `1440x900` and mobile `390x844`;
- signed-out identity journey;
- controlled authenticated Radar shell;
- keyboard focus traversal;
- horizontal overflow;
- axe WCAG 2a/2aa/21aa with serious/critical findings blocking CI;
- fail-closed unhandled API request detection.

The gate discovered real contrast and accessible-name defects. The product UI was corrected; no axe threshold was weakened. Controlled co-mounted module fixtures remain deliberately empty/unconfigured and do not claim provider or production-data truth.

Final PR head `703764039c45a2e8eb502e53b60307df2aaa4679` passed canonical PR CI run `34978609396`. Squash merge `f1b3009e126faf6d388b1e5dca7e681c8e991ac6` passed merged-main CI run `34979049457` and was deployed successfully to app/migrator production services.

## What is no longer a current gap

The following historical statements or prior gap descriptions are superseded by merged and production evidence:

- Identity has not yet reached the database.
- Instagram migrations 017/018 are merely pending production application.
- Publishing, analytics, experiments, automation and commercial foundations are entirely future phases.
- Production is only reconciled through migrations 030–033 or through 059.
- Publication worker dead-letter behavior is unbounded or invisible to the application.
- Retry/dead-letter/reconciliation lacks controlled production operational proof.
- Cancellation lacks production operational proof.
- Production cannot identify the exact deployed code SHA.
- CI/Railway dependency installation lacks a committed lockfile and explicit `npm ci` path.
- The project lacks a canonical automated responsive/accessibility/cross-browser browser gate.

They remain in chronological roadmap history only to preserve the sequence of decisions and execution.

## Production-hardening note: Railpack/Corepack

A package-manager hardening attempt exposed a Railway/Railpack 0.39 tooling incompatibility:

1. PR #167 committed `package-lock.json` and moved CI to `npm ci` successfully.
2. PR #168 added `packageManager: npm@10.9.8`; normal builds succeeded.
3. After `RAILPACK_INSTALL_CMD=npm ci --no-audit --no-fund` was enabled on the three canonical services, all new builds failed while packaging `/opt/corepack`, with `lstat /opt/corepack: no such file or directory`.
4. PR #169 removed only the Corepack-triggering `packageManager` field while preserving lockfile + explicit Railway `npm ci`.
5. Exact-SHA CI passed; app, migrator and worker rebuilt successfully with `npm ci` and no `/opt/corepack` packaging path.
6. PR #173 production builds again confirmed the explicit `npm ci --no-audit --no-fund` contract while the cosmetic Railpack recommendation remained non-blocking.

Railpack may still display a recommendation to specify a package-manager version. This is treated as a cosmetic tool warning rather than a reason to reintroduce a configuration proven to break canonical builds.

## Current critical path to freeze

1. Exercise the main authenticated production browser journeys on the accepted runtime lineage and fix every reproducible defect when a real authenticated production session/test credential is available.
2. Produce controlled real-provider publication evidence only where provider configuration, permissions, account state and explicitly authorized content permit it.
3. Complete same-task competitive design evidence and final visual freeze. Automated responsive/accessibility/cross-browser evidence is already closed.
4. Consolidate the final evidence package and run the final Claude/adversarial review using an actual reviewer/tool.
5. Run the remaining authenticated/data portion of the final Production Truth Gate: exact SHA/deployment/health are proven; frontend -> authenticated API -> real data -> expected result remains to be captured.
6. Freeze only after all applicable critical gates pass or an explicit evidence-bounded external limitation is documented.

## Completion rule

Growth OS is not declared complete by code volume, individual green PRs or synthetic provider tests. It reaches 100% only when the applicable Phase 11 acceptance gates and final freeze record are complete on one accepted production lineage, with external/provider limitations explicitly separated from internally verifiable product defects.
