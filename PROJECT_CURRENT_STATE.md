# Current Project State

## Mandatory continuation-request log

Every request to continue this project, including repeated or abbreviated requests, must receive a separate dated entry in `docs/PROJECT_EXECUTION_MEMORY.md`. Record the exact available request text, verified starting point, every performed action/attempt/check/correction, actual result, any blocker and the next pending action. Consult the last entry before resuming and update the central record during work and before ending the response. A request is not execution evidence. Preserve repetitions and history; never invent unavailable messages, timestamps or results, and never reproduce secrets. Full standing instruction: central memory, “Regra permanente — registrar cada pedido de continuação — v1.0 — 2026-09-15”.

Last updated: 2026-09-16  
Purpose: single operational checkpoint for resuming Growth OS work without relying on chat memory.

## Repository and lineage

- Repository: `dbdanielbaracho/GROWTH-OS`.
- Current accepted application runtime after PR #182: `d2794e8286672af0fcf7809f0b09241d89b8b0d4`. Prior PR #180/#173 runtime evidence is preserved below. Documentation-only main commits must be tracked separately.
- PR #173, `test: add cross-browser responsive accessibility gate`, is merged; its historical production SHA is recorded below. PR #182 is the current accepted application runtime.
- Documentation-only commits after the accepted runtime SHA must be tracked separately from serving runtime identity. Railway Watch Paths are configured and physically proven to filter docs-only changes.
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
- PR #171/#172: documentation-only Watch Path acceptance and regression proof.
- PR #173: automated Chromium/Firefox/WebKit responsive/accessibility browser gate plus accessibility fixes discovered by that gate.
- Detailed execution logs:
  - `docs/EXECUTION_LOG_2026-09-15_PRODUCTION_HARDENING.md`
  - `docs/EXECUTION_LOG_2026-09-15_WATCH_PATH_HARDENING.md`
  - `docs/EXECUTION_LOG_2026-09-15_BROWSER_QUALITY_GATE.md`
- Roadmap current-status companion: `docs/ROADMAP_STATUS_RECONCILIATION_2026-09-15.md`.

## Canonical production

Railway project: `successful-embrace`  
Environment: `production`

Canonical services:

- `growth-os`
- `migrator`
- Postgres
- `growth-os-publication-worker`

Current accepted application evidence after PR #180 (2026-09-16):

- runtime SHA: `2c70a33cb6bb4bfbce7e6a1e61cd5c090ac64aac`;
- PR-head CI `35045212581` and exact merged-main CI `35045369593`: SUCCESS;
- application deployment `9fd77faf-bce0-47c9-a610-0ebefe510698`: SUCCESS;
- public `/v1/deployment` confirms that exact SHA/deployment; health ready/database ok;
- real secure signin/signout/signin on the same page, secondary-panel visibility, pointer access to Analytics and corrected 152/152 counts: verified;
- content read/edit form exercised without saving; one v1 draft / zero publication intents; no horizontal panel overflow;
- migrator and worker unchanged by Watch Paths. Migrator SHA `f1b3009e126faf6d388b1e5dca7e681c8e991ac6`; worker SHA `1ad55eb293fb19f6fa0107e6d39073950414c47d`. Do not claim all services share the application SHA.

Historical accepted serving runtime evidence after PR #173:

- accepted runtime SHA: `f1b3009e126faf6d388b1e5dca7e681c8e991ac6`;
- merged-main GitHub CI run `34979049457`: `SUCCESS`;
- `growth-os` deployment `57cb874b-2dc9-4055-b64b-b5da38138a5e`: `SUCCESS`;
- app startup verified exact Railway commit `f1b3009e126faf6d388b1e5dca7e681c8e991ac6` and deployment ID `57cb874b-2dc9-4055-b64b-b5da38138a5e`;
- Railway health probe `GET /health/ready`: HTTP 200;
- custom host `growos.predibeacon.com` is receiving production ingress;
- `migrator` deployment `1c80b068-cb44-4b65-9e13-b64538c61211`: `SUCCESS` on the same SHA;
- `growth-os-publication-worker` deployment `f308f3f1-0301-4859-91dc-34ca04a56917`: `SUCCESS` and intentionally unchanged by PR #173;
- production dependency installation remains explicitly `npm ci --no-audit --no-fund` via `RAILPACK_INSTALL_CMD` on app, migrator and worker.

The committed `package-lock.json` plus explicit `npm ci` is the accepted deterministic install contract. The Railpack package-manager-version recommendation remains cosmetic because the tested explicit Corepack route caused a reproducible packaging failure.

## Automated browser quality gate

PR #173 closes the automated browser-quality portion of final acceptance.

Canonical coverage:

- Playwright `1.63.0` and `@axe-core/playwright` `4.13.0`, installed CI-only with no lockfile mutation;
- Chromium, Firefox and WebKit;
- signed-out identity journeys;
- authenticated Radar shell with controlled UI fixtures;
- desktop `1440x900` and mobile `390x844`;
- keyboard traversal;
- horizontal overflow checks;
- axe `wcag2a`, `wcag2aa`, `wcag21aa`;
- fail on serious/critical accessibility violations;
- fail on unhandled `/v1/**` requests.

The gate exposed and caused correction of real product issues rather than being weakened:

- signed-out authentication contrast defects;
- Radar metric contrast defects;
- automation selector lacking an accessible name;
- co-mounted module API calls were explicitly mocked only with controlled empty/unconfigured fixtures, while unknown API calls remain fail-closed.

Final PR head `703764039c45a2e8eb502e53b60307df2aaa4679` passed canonical CI run `34978609396`, including the browser Test step. The temporary diagnostics workflow used while retrieving Playwright traces/results was removed before merge.

Evidence boundary: these fixtures prove UI/browser behavior only. They do not prove real provider state, authenticated production account behavior, factual production opportunity data, or real publication.

## Railway Watch Path hardening

Documentation-only merges previously triggered unnecessary app/migrator builds. Watch Paths are explicitly configured and physically proven.

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

PR #171/#172 proved docs-only merges leave the canonical deployments unchanged. PR #173 provided the complementary positive proof: a web/package change redeployed app and migrator while the worker correctly remained unchanged.

Operational rule: distinguish repository head from serving runtime SHA. At final freeze, explicitly record the accepted runtime SHA; if documentation-only commits follow it, record both lineages or deliberately redeploy the accepted freeze SHA only when a runtime-affecting change requires it.

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

Current production migrator proof on deployment `1c80b068-cb44-4b65-9e13-b64538c61211`:

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
- Automated desktop/mobile, keyboard, WCAG serious/critical and Chromium/Firefox/WebKit browser-quality gate in canonical CI.

## Closed acceptance gaps

The following are closed by physical CI/production evidence:

1. Operational retry/dead-letter/reconciliation proof.
2. Cancellation operational proof.
3. Technical production SHA/deployment-ID/health traceability.
4. Migration reconciliation through 060.
5. Deterministic npm installation in CI and Railway canonical services.
6. Railpack/Corepack failure introduced by the first package-manager hardening attempt.
7. Documentation-only unnecessary Railway redeploys.
8. Automated responsive/accessibility/cross-browser evidence for the signed-out identity journey and controlled authenticated Radar shell, across Chromium/Firefox/WebKit with serious/critical axe gating.

## Remaining acceptance gaps

Growth OS is materially advanced but is not yet legitimately 100% complete.

1. **Remaining authenticated production browser end-to-end validation**: real signin/signout/re-entry, selected workspace, Radar/provider/content/analytics reads and panel regressions are verified after PR #180. Still required on the accepted production lineage: signup/onboarding, workspace switching/isolation, content CREATE/review/approval, provider/publication operations and failure/recovery states using real authenticated production accounts and appropriate approved content.
2. **Controlled real-provider publication evidence** only where provider permissions/account configuration and explicitly authorized content permit it. No real-publish claim without provider-side confirmation.
3. **Same-task competitive visual comparison and final visual freeze.** Automated responsive/accessibility/cross-browser coverage is closed; competitive/final visual acceptance remains separate.
4. **Final consolidated adversarial review** only at the project/freeze gate. Claude is not an intermediate micro-gate and must not be claimed as completed without an actual review.
5. **Final Production Truth Gate authenticated/data chain**: exact public runtime SHA, deployment and health are proven. Native authenticated read paths for Radar/provider/content/analytics and expected panel behavior passed in PR #180 and remain available after PR #182. Remaining write/isolation/provider chains and final consolidated acceptance are still open; controlled fixtures are never factual production evidence.

## Next execution order

1. Keep `main` as the only technical baseline; do not revive stale feature branches.
2. Exercise authenticated production browser journeys and fix every reproducible runtime defect when a real authenticated session/test credential is available.
3. Produce controlled real-provider publication evidence only with explicit approved content/account and provider confirmation.
4. Complete same-task competitive design comparison and final visual freeze.
5. Consolidate the final evidence package and run the final Claude/adversarial review using an actual reviewer/tool.
6. Run the remaining authenticated/data portion of the Production Truth Gate on the accepted runtime lineage.
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

## Latest resumption record — 2026-09-15

The user supplied `Registro_Completo_Chat_Growth_OS_2026-09-15.docx` and requested: "verificar o documento e mesclar projeto e incluir O **PR #176**". The source was read, its 139 nonempty text blocks/29 tables preserved in order, and all three embedded screenshots inspected. Full source archive: `docs/sources/Registro_Completo_Chat_Growth_OS_2026-09-15.docx`; textual import and reconciliation: `docs/CONVERSATION_IMPORT_2026-09-15_TINYFISH_GROWTH_OS.md`. This resolves the missing historical Tinyfish operational record. The source is a consolidated record, not a complete verbatim transcript or a separate Tinyfish-generated report.

Historical Tinyfish state from the supplied source: connected; strict/custom-max-steps attempts rejected by beta constraints; default run reached signed-out Growth OS; direct user login did not persist into a later ephemeral run; a suggested profile URL returned 404 and was corrected. Screenshots end at Agent dashboard with eight aggregate successful runs, which do not establish Growth OS authenticated acceptance. Next operational gap: locate a correct persistent Browser Context Profile/session and validate actual authenticated production journeys.

PR #176 is explicitly included: merged; head `b651958fbb4476bca140deec6bf9c8ab6ab4b087`; merge `920e31fc93e102e9493b1c41cef06ce01f199087`; CI run `35003401649` success on the exact head. Its rule to log every continuation request remains mandatory at the start of this checkpoint and the central memory.

The source's `main ad4dad727012b92cbe9c3675d5994016ec8a1488` is historical (PR #174). The verified import base is `5cc3246f7bfc5175b7ef1fb6087c90fd5c6561ac` after documentation PRs #175/#176/#177. Import PR #178 provides final CI/merge evidence. Documentation advances are separate from the accepted runtime SHA; no new Railway deployment was performed in this import.

The native secure production login request in the subsequent resumption was rejected by automatic approval review and remains recorded in `docs/EXECUTION_LOG_2026-09-15_AUTHENTICATED_ACCEPTANCE_BLOCKER.md` / PR #175. The historical source does not override that rejection. No Tinyfish call, authentication, real publication or Claude review was executed in this import.

PR #177's three recovered messages remain preserved; `docs/CONVERSATION_RECOVERY_2026-09-15_TINYFISH_PARTIAL.md` now links the fuller operational source. Consult the appended central-memory entry “importação do documento anterior e inclusão explícita do PR #176” for this request, all actions, corrections, source limits and next pending work.


## Latest continuation — 2026-09-16 — Tinyfish profile readiness

Exact request: "continuar". Verified documentation base: `d6b3c3612d51b7f6af623629f5af8384a7b43892` (PR #178). Every continuation remains separately recorded in the central execution memory; PR #176 rule is unchanged.

Public production reconfirmed through Tinyfish Fetch with TTL zero: health ready/database ok, signed-out landing, and canonical `GET /v1/deployment` reporting runtime `f1b3009e126faf6d388b1e5dca7e681c8e991ac6` / deployment `57cb874b-2dc9-4055-b64b-b5da38138a5e`. Legacy `/v1/system/info` returns 404 and is not the current metadata contract. No deployment or authenticated acceptance claim.

Official Tinyfish profile lifecycle and initial authenticated read-only matrix are prepared in `docs/EXECUTION_LOG_2026-09-16_TINYFISH_PROFILE_READINESS.md`. Search/Fetch calls succeeded; no authenticated automation or profile setup was run. Profile management methods are not exposed by this session's connector; no concrete default/profile ID has been retrieved.

The prior automatic-review rejection of production credential request/submission remains active. Next dependent step: explicit authentication authorization for the exact Growth OS origin through the secure form, then set up/save/reuse a persistent profile and run actual production journeys. Do not circumvent the rejection through vault or another automation. Documentation PR #179 supplies final checks/merge evidence; core acceptance gates remain open.


## Authorized authenticated execution — 2026-09-16

The user explicitly authorized the secure Growth OS login ("sim autorizo"). The secure request returned submitted and fresh DOM confirmed signed-in Growth OS, workspace Crescimento and real persisted Radar/provider/content/analytics surfaces. A second native-browser tab stayed authenticated. The historical PR #175 rejection remains preserved but missing user authorization no longer describes the current attempt.

Authenticated read-only evidence and discovered defects: `docs/EXECUTION_LOG_2026-09-16_AUTHENTICATED_PANEL_ACCEPTANCE.md`. PR #180 corrects missing secondary panels after same-page signin, stale session reads, Analytics/YouTube overlap, numeric count concatenation and long draft layout. CI, merge and a fresh production browser pass remain required before accepting its runtime.

No Tinyfish Browser Context Profile was created or checked; reuse across two native tabs is a separate fact. No existing content was saved/approved and no external post was published. Initial accepted production runtime remains f1b3009… until new deployment proof. Remaining provider publication, write-path production acceptance, final competitive visual/Claude/freeze gates are still open.


## Accepted authorized continuation — 2026-09-16

PR #180 is merged/deployed/verified on runtime `2c70a33cb6bb4bfbce7e6a1e61cd5c090ac64aac`. All action/failure/correction/CI/production evidence is in `docs/EXECUTION_LOG_2026-09-16_AUTHENTICATED_PANEL_ACCEPTANCE.md` and the central execution memory. Documentation closure PR #181 tracks the final record/checks/merge. Historical dated blockers/checkpoints above remain as history; current authorization and secure native login succeeded.

Tinyfish profile-reuse run d1fecfb9-da09-4436-922b-6fdddd8044dc completed signed out. Native-browser reuse is verified separately. Default/profile ID and Tinyfish profile setup/save remain unverified, and management methods are absent from the exposed connector. Do not rerun identical signed-out automations or claim a profile exists based on use_profile alone.

Next pending work: valid Tinyfish profile setup/save for repeated Tinyfish runs; remaining production write/provider journeys with an appropriate approved account/content; competitive visual/final Claude/freeze gates. No publish permission or 100% completion claim from this execution.


## Latest continuation — 2026-09-16 — explicit publication account selection

Exact request: "continuar". Starting main `68f630c5e2b5f4ad860bfcc40fe90c13a029b0b2` / serving runtime `2c70a33cb6bb4bfbce7e6a1e61cd5c090ac64aac`, confirmed live. Native authenticated session remains active; existing draft untouched. Code inspection identified implicit first-account selection despite the Choose account placeholder. Fix requires an explicit matching connected account and clears choices on session transitions; panel copy clarifies Execute can publish. Real approved-draft publication was not exercised. Implementation, CI and post-deploy acceptance: `docs/EXECUTION_LOG_2026-09-16_PUBLICATION_ACCOUNT_SELECTION.md` and its PR closing summary.

Tinyfish persistent-profile setup/save remains pending and administrative methods are not exposed. No repeated signed-out run. The PR #180 authenticated read-only/data path is accepted; remaining write/onboarding/workspace-isolation/provider paths and final visual/Claude/freeze are separate open gates. Preserve all historical dated entries above.


## Accepted latest continuation — 2026-09-16 — PR #182

Current application runtime: `d2794e8286672af0fcf7809f0b09241d89b8b0d4`; app deployment `c9f9b133-e1c1-44c5-838b-e824b215d359` SUCCESS. Exact PR CI `35047702029` and main CI `35047904556` success. /v1/deployment matches; health ready/database ok. Browser session preserved; four panels/Radar/providers visible; Create has corrected copy, one untouched draft, zero intents and zero panel overflow. Explicit-account preparation/platform/reset regression is CI-only because this real workspace has no approved draft. No production write/publication performed.

Complete request/action/correction/evidence record: `docs/EXECUTION_LOG_2026-09-16_PUBLICATION_ACCOUNT_SELECTION.md` and central memory. Documentation closure [PR #183](https://github.com/dbdanielbaracho/GROWTH-OS/pull/183) records final checks/merge separately from runtime. Migrator/worker correctly unchanged, active SUCCESS SHAs f1b3009… / 1ad55eb… verified. Tinyfish profile setup/save still requires dashboard/API administration unavailable in the exposed connector; instructions and two-run read-only verification plan recorded. Remaining production write/provider/isolation and final visual/Claude/freeze gates remain open.
