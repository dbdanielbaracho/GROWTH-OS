# Current Project State

Last updated: 2026-09-15  
Purpose: single operational checkpoint for resuming Growth OS work without relying on chat memory.

## Repository and lineage

- Repository: `dbdanielbaracho/GROWTH-OS`.
- Repository `main` before this checkpoint update: `a5ceab0ed8b43c65601e667e213c8764df4cf6b4`.
- The last runtime-affecting production lineage is still `b9b16be8717b9f17cc6f92fa601056e1fee69cc2`; subsequent merged work has been documentation-only and is intentionally filtered by Railway Watch Paths.
- Historical stale PRs #29, #38, #49 and #65 were closed without merge after their valid work was proven already present or safely ported.
- PR #154: bounded publication retries and terminal `dead` behavior.
- PR #155: Instagram authorization timeout-state correction.
- PR #156: design-quality benchmark v0.2.
- PR #158: safe publication queue-status projection and user-facing terminal dead-letter mapping.
- PR #163: migration 060 / least-privilege reconciliation runtime grants.
- PR #164: production cancellation smoke and operational proof.
- PR #165/#166: public non-secret deployment metadata and fail-closed Railway production identity.
- PR #167: canonical `package-lock.json` and CI `npm ci`.
- PR #168/#169: npm/Railpack hardening, discovery of the `/opt/corepack` failure, and recovery while retaining deterministic `npm ci`.
- PR #170: canonical production-hardening documentation refresh.
- PR #171: documentation-only Watch Path acceptance test; CI #1029 fully green, squash merge `a5ceab0ed8b43c65601e667e213c8764df4cf6b4`, and no Railway canonical service redeployed.
- Detailed execution logs:
  - `docs/EXECUTION_LOG_2026-09-15_PRODUCTION_HARDENING.md`
  - `docs/EXECUTION_LOG_2026-09-15_WATCH_PATH_HARDENING.md`
- Roadmap current-status companion: `docs/ROADMAP_STATUS_RECONCILIATION_2026-09-15.md`.

## Canonical production

Railway project: `successful-embrace`  
Environment: `production`

Canonical services:

- `growth-os`
- `migrator`
- Postgres
- `growth-os-publication-worker`

Current serving runtime evidence:

- `growth-os` deployment `72b6de52-9f4c-40d0-b30f-9dff74108523`: `SUCCESS`.
- App startup verified exact Railway commit `b9b16be8717b9f17cc6f92fa601056e1fee69cc2` and that deployment ID.
- `/health/ready`: HTTP 200.
- `migrator` deployment `e910d6c2-7732-4623-84a6-9d74997ef026`: `SUCCESS`.
- `growth-os-publication-worker` deployment `f308f3f1-0301-4859-91dc-34ca04a56917`: `SUCCESS`.
- Production dependency installation is explicitly `npm ci --no-audit --no-fund` via `RAILPACK_INSTALL_CMD` on app, migrator and worker.
- The committed `package-lock.json` plus explicit `npm ci` is the accepted deterministic install contract. The Railpack package-manager-version recommendation remains cosmetic because the tested explicit Corepack route caused a reproducible packaging failure.

## Railway Watch Path hardening

Documentation-only merges previously triggered unnecessary app/migrator builds. Watch Paths are now explicitly configured and physically proven.

`growth-os`:

- `/apps/**`
- `/packages/**`
- `/db/**`
- `/package.json`
- `/package-lock.json`

`migrator`:

- `/db/**`
- `/packages/**`
- `/package.json`
- `/package-lock.json`
- `/apps/api/package.json`
- `/apps/web/package.json`

`growth-os-publication-worker`:

- `/apps/api/**`
- `/packages/**`
- `/db/**`
- `/package.json`
- `/package-lock.json`

PR #171 was the acceptance test. Before and after its documentation-only merge the canonical deployment IDs remained exactly:

- app `72b6de52-9f4c-40d0-b30f-9dff74108523`;
- migrator `e910d6c2-7732-4623-84a6-9d74997ef026`;
- worker `f308f3f1-0301-4859-91dc-34ca04a56917`.

Therefore docs-only changes no longer create unnecessary production builds.

Operational rule: distinguish repository head from serving runtime SHA. At final freeze, explicitly record the accepted runtime SHA; if documentation-only commits follow it, either record both lineages or deliberately redeploy the final accepted freeze SHA.

## Canonical database state

Production migration reconciliation is confirmed through migration 060.

- Identity/provider foundations: 006, 009, 014–021.
- Publication contracts/operations: 022–032.
- Analytics, recommendation, experiment, automation and commercial controls: 033–039.
- Identity/runtime privilege corrections: 040–045.
- Managed-account/provider runtime corrections: 046–055.
- Publication worker principal/security reconciliation: 056–058.
- Safe publication queue-status projection: 059.
- Publication reconciliation runtime privileges: 060.

Current production migrator proof on deployment `e910d6c2-7732-4623-84a6-9d74997ef026`:

- migration 060: already present;
- `Production migration reconciliation complete`;
- publication queue/dead-letter smoke: `PASS queued -> leased(1) -> retry_wait -> leased(2) -> dead; rollback complete`;
- publication reconciliation smoke: `PASS ambiguous -> needs_user_action -> matched -> confirmed; immutable replay rejected; rollback complete`;
- publication cancellation smoke: `PASS actor mismatch rejected; scheduled -> cancelled; cancelled/confirmed blocked; rollback complete`.

These are controlled database/worker operational proofs and do not claim an external provider post was created.

## Product capabilities already present

- Authenticated identity/workspace foundation with tenant-scoped runtime controls.
- YouTube connection/sync product path, typed API contracts and technical design.
- Instagram professional-account authorization, media/metrics sync and Growth Intelligence path.
- Opportunity Radar and editorial high-contrast design baseline.
- Content authoring, append-only versioning, review and approval controls.
- Publication intent, claim/finalization, assets, execution adapters, retry scheduling, cancellation and reconciliation.
- Dedicated publication worker service principal, runtime context, continuous worker process and Railway service.
- Bounded retries with terminal dead-letter state.
- Safe queue-status projection mapping terminal queue `dead` to `needs_user_action` without exposing internal payload/lease/service-principal data.
- Production queue/dead-letter, reconciliation and cancellation operational smoke coverage.
- Metric analytics summary, quality/anomaly contracts and authenticated analytics surface.
- Recommendation/feedback lineage, experiment lineage and controlled automation policy.
- Commercial entitlements / workspace governance foundation.
- Design-quality benchmark v0.2 with evidence boundaries and final/freeze acceptance gates.
- Public deployment metadata endpoint and fail-closed Railway production identity invariant.
- Deterministic dependency install contract in both CI and canonical Railway services.
- Cost/deploy hardening through validated Watch Paths.

## Closed acceptance gaps

The following are closed by physical production evidence:

1. Operational retry/dead-letter/reconciliation proof.
2. Cancellation operational proof.
3. Technical production SHA/deployment-ID/health traceability.
4. Migration reconciliation through 060.
5. Deterministic npm installation in CI and Railway canonical services.
6. Railpack/Corepack failure introduced by the first package-manager hardening attempt.
7. Documentation-only unnecessary Railway redeploys.

## Remaining acceptance gaps

Growth OS is materially advanced but is not yet legitimately 100% complete.

1. **Authenticated end-to-end browser validation** on the latest accepted production lineage: signup/signin/session/workspace, Instagram/YouTube states, content CREATE/review/approval, publication operations and failure/recovery states.
2. **Controlled real-provider publication evidence** where provider permissions/account configuration and explicitly authorized content permit it. No real-publish claim without provider-side confirmation.
3. **Final responsive/accessibility/cross-browser evidence** and same-task competitive design comparison before visual freeze.
4. **Final consolidated adversarial review** only at the project/freeze gate. Claude is not an intermediate micro-gate and must not be claimed as completed without an actual review.
5. **Final Production Truth Gate authenticated/data chain**: public URL and technical deployment identity are proven; frontend -> authenticated API -> real data -> expected result must still be captured on the final accepted runtime lineage.

## Next execution order

1. Keep `main` as the only technical baseline; do not revive stale feature branches.
2. Exercise authenticated end-to-end journeys and fix every reproducible runtime defect.
3. Produce controlled real-provider publication evidence only with authorized account/content and provider confirmation.
4. Complete responsive/accessibility/cross-browser/competitive evidence.
5. Consolidate the final evidence package and run the final adversarial review.
6. Run the remaining authenticated/data portion of the Production Truth Gate on one accepted runtime SHA.
7. Freeze only after all applicable gates pass or an explicit evidence-bounded external limitation is documented.

## Operating rules

- Always verify live `main`, PR head and serving runtime SHA before CI/merge/deploy/acceptance claims.
- CI success is necessary but not sufficient for production acceptance.
- Railway production evidence must come from the canonical project/environment and exact deployment lineage.
- Never infer provider success from a redirect, local test or synthetic adapter response.
- Never use synthetic data as proof of a factual opportunity, provider result or real production journey.
- Keep database/worker validation, application-runtime validation and browser/provider validation as separate gates.
- A tooling warning is not a product failure, but any tooling change that breaks canonical builds must be reverted/fixed before acceptance.
- Documentation-only repository head advances do not imply a new serving runtime deployment after Watch Path hardening.
- Record material execution, failures, fixes and acceptance evidence in GitHub so chat memory is not the source of truth.
