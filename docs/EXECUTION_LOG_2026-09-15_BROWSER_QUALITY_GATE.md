# Growth OS — Browser Quality Gate Execution Log

Date: 2026-09-15  
Scope: PR #173 — cross-browser, responsive and accessibility quality gate  
Evidence boundary: controlled browser fixtures validate UI behavior and accessibility only. They are not evidence of real provider publication, factual provider data, or authenticated production account behavior.

## 1. Objective

Close the automated browser-quality acceptance gap by adding a CI-only gate that exercises the real React application in Chromium, Firefox and WebKit, at desktop and mobile viewport sizes, without adding browser tooling to production dependencies or changing the canonical lockfile.

The gate was required to fail on serious/critical WCAG findings, horizontal overflow, broken keyboard traversal, expected UI regressions, or any unhandled `/v1/**` request.

## 2. Tooling and integration

Exact CI-only browser tooling:

- `@playwright/test@1.63.0`
- `@axe-core/playwright@4.13.0`

The runner installs these only in CI with:

`npm install --no-save --package-lock=false --no-audit --no-fund @playwright/test@1.63.0 @axe-core/playwright@4.13.0`

Browser binaries are installed for Chromium, Firefox and WebKit. No production dependency or committed `package-lock.json` mutation is used for this tooling.

The canonical web test script now runs the existing Node tests and then the browser-quality runner. Therefore the repository CI command `npm run test --workspaces --if-present` executes this gate automatically.

## 3. Browser coverage

The gate exercises:

- signed-out identity flows;
- authenticated Opportunity Radar shell using controlled API fixtures;
- desktop viewport `1440x900`;
- mobile viewport `390x844`;
- Chromium;
- Firefox;
- WebKit;
- keyboard focus traversal;
- horizontal overflow checks;
- axe tags `wcag2a`, `wcag2aa`, `wcag21aa`;
- failure on serious or critical accessibility violations;
- fail-closed tracking of unhandled `/v1/**` requests.

Controlled authenticated fixtures represent an isolated UI-test workspace/opportunity and are explicitly not used as provider, publication or production-data acceptance evidence.

## 4. Failures discovered and corrected

### 4.1 Playwright configuration module mismatch

The first executable browser run failed before any browser assertion. Playwright loaded the TypeScript configuration through a CommonJS path, while the diagnostic output path used `import.meta.url`.

Observed failure:

`SyntaxError: Cannot use 'import.meta' outside a module`

Correction:

- use `process.cwd()` for repository-root diagnostic paths;
- preserve the same browser gate criteria.

This was an infrastructure correction only; no acceptance criterion was weakened.

### 4.2 Real accessibility findings — signed-out identity UI

Once the browsers executed, axe identified serious contrast failures in the signed-out authentication surface.

Correction applied to the real UI:

- explicit accessible foreground colors in the light authentication card;
- accessible title/copy/form/button colors independent of the dark editorial root palette;
- corrected workspace picker text contrast.

The axe threshold remained unchanged.

### 4.3 Real accessibility findings — Radar

Axe also identified insufficient contrast in Radar metric tiles and a select control without an accessible name.

Corrections applied to the real UI:

- metric tile background/foreground contrast aligned with the dark editorial palette;
- `aria-label="Automation action"` added to the automation action selector.

Again, no axe rule or severity threshold was disabled.

### 4.4 Co-mounted application modules

The production web shell mounts multiple modules from the same page. After the real UI/accessibility failures were corrected, authenticated browser tests correctly detected additional legitimate API requests from the YouTube, Instagram, analytics, content and publication modules.

The browser fixture router was extended with explicit controlled responses for only these known routes:

- `/v1/integrations/youtube/status` — configured false, no integrations;
- `/v1/integrations/instagram/status` — configured false, no integrations;
- `/v1/analytics/metrics` — empty metrics;
- `/v1/content` — empty content;
- `/v1/publication-intents` — empty publication intents.

Unknown `/v1/**` requests still cause the test to fail. This preserves fail-closed behavior while avoiding false failures from legitimate co-mounted modules.

## 5. Temporary diagnostics

A temporary workflow `Browser Quality Diagnostics` was added only to make Playwright JSON, traces and screenshots retrievable while the original canonical CI log path was difficult to inspect.

It was used to locate the real failures above and was then deleted before merge.

The final PR does not contain the temporary diagnostics workflow.

## 6. Final PR evidence

Final PR head before merge:

`703764039c45a2e8eb502e53b60307df2aaa4679`

Canonical PR CI:

- run `34978609396`;
- job `104412729923`;
- result: `SUCCESS`;
- Test Integrity Gate: PASS;
- Release hardening gate: PASS;
- Typecheck: PASS;
- Build: PASS;
- all canonical migrations/SQL gates: PASS;
- Growth Intelligence integration: PASS;
- Production same-origin web shell gate: PASS;
- final Test step, including Chromium/Firefox/WebKit browser gate: PASS.

PR #173 squash merge:

`f1b3009e126faf6d388b1e5dca7e681c8e991ac6`

Merged-main CI:

- run `34979049457`;
- event: `push` to `main`;
- exact SHA: `f1b3009e126faf6d388b1e5dca7e681c8e991ac6`;
- result: `SUCCESS`.

## 7. Railway production evidence

Railway Watch Paths behaved exactly as intended for the merged changes:

- `growth-os`: redeployed because the web application/package changed;
- `migrator`: redeployed because `/apps/web/package.json` is an explicit migrator watch path;
- `growth-os-publication-worker`: did not redeploy because no worker-relevant path changed.

### App

Deployment:

`57cb874b-2dc9-4055-b64b-b5da38138a5e`

Result: `SUCCESS`

Railway metadata identifies exact commit:

`f1b3009e126faf6d388b1e5dca7e681c8e991ac6`

Build evidence:

- Railpack 0.39.0;
- deterministic install command `npm ci --no-audit --no-fund`;
- API build PASS;
- web TypeScript/Vite build PASS.

Runtime evidence:

- `verified Railway deployment identity`;
- commit SHA `f1b3009e126faf6d388b1e5dca7e681c8e991ac6`;
- deployment ID `57cb874b-2dc9-4055-b64b-b5da38138a5e`;
- server listening on port 8080;
- Railway health probe `GET /health/ready` returned HTTP 200;
- custom host `growos.predibeacon.com` is receiving production ingress.

The Railpack recommendation to specify package-manager version remains a cosmetic warning. The previously tested `packageManager`/Corepack route is intentionally not restored because it caused the accepted reproducible `/opt/corepack` packaging failure.

### Migrator

Deployment:

`1c80b068-cb44-4b65-9e13-b64538c61211`

Result: `SUCCESS`

Exact merge SHA:

`f1b3009e126faf6d388b1e5dca7e681c8e991ac6`

Production evidence:

- migrations reconciled through 060;
- `Production migration reconciliation complete`;
- publication queue/dead-letter smoke: `PASS queued -> leased(1) -> retry_wait -> leased(2) -> dead; rollback complete`;
- publication reconciliation smoke: `PASS ambiguous -> needs_user_action -> matched -> confirmed; immutable replay rejected; rollback complete`;
- publication cancellation smoke: `PASS actor mismatch rejected; scheduled -> cancelled; cancelled/confirmed blocked; rollback complete`.

### Publication worker

Deployment remained unchanged as expected:

`f308f3f1-0301-4859-91dc-34ca04a56917`

Status: `SUCCESS`.

This is an additional physical confirmation that Railway Watch Paths did not redeploy the worker for a web-only change.

## 8. Acceptance conclusion

Closed by PR #173 and the matching production lineage:

- automated desktop/mobile horizontal-overflow coverage;
- automated keyboard traversal coverage for the signed-out identity journey;
- automated serious/critical WCAG axe gate;
- Chromium, Firefox and WebKit coverage;
- real accessibility defects discovered by the gate and corrected in the product UI;
- merged-main CI proof;
- production app and migrator exact-SHA deployment proof;
- production health and database operational smoke continuity.

Not closed by this evidence and explicitly still separate:

1. authenticated production browser end-to-end proof using a real production session/account;
2. controlled real-provider publication proof with explicitly approved content/account/provider authorization;
3. same-task competitive visual comparison and final visual freeze;
4. final Claude/adversarial review using an actual reviewer/tool;
5. remaining authenticated/data chain of the final Production Truth Gate.

No synthetic browser fixture is evidence for any of those five items.
