# Growth OS — Copilot & Autopilot Operations Runbook

Status: operational acceptance candidate  
Scope: conversational Copilot, evidence boundaries, Autopilot approval/execution, data-quality alerts and recovery.

## 1. Safety contract

- Copilot is read-only and evidence-grounded. It reads only persisted data available to the authenticated workspace.
- Copilot must not invent provider observations, causal claims, recommendations, experiment outcomes or operational state.
- Copilot never publishes, approves or executes provider actions.
- Autopilot actions remain separated into request -> approval -> explicit execution.
- Provider publication is successful only after the persisted publication intent reaches `confirmed`.
- The workspace emergency stop (`kill_switch`) blocks new automated execution when active.
- Tenant boundaries, RBAC and the existing publication/reconciliation controls remain authoritative.

## 2. Operator signals

The Copilot workspace pulse surfaces:

- current opportunities and insights;
- seven-day metric groups;
- analytics quality alerts;
- experiment count;
- automation requests in `executing`, `needs_input` or `failed`;
- emergency-stop state.

The Analytics panel separately surfaces incomplete/stale observations returned by the canonical anomaly endpoint.

## 3. Incident classes and response

### Copilot cannot read evidence

Expected behavior: fail closed and show that no answer was invented.

Check, in order:
1. authenticated session and selected workspace;
2. API/database health;
3. tenant-scoped access to Opportunity Radar, analytics, recommendations, experiments and automation policy;
4. whether real provider observations/evidence actually exist.

Do not replace missing evidence with fixtures in production.

### Data-quality alert

A quality alert means the affected metric window includes incomplete or stale observations. Keep the metric visible with its warning, but do not promote the affected value as clean evidence until the provider data is refreshed or the limitation is documented.

### Automation `needs_input`

Inspect the stored `execution_error_class` and result reference. For publishing, reconcile ambiguous provider outcomes before any retry that could duplicate an external post.

### Automation `failed`

Do not mark the request successful manually. Fix the reproducible defect or provider prerequisite, then execute through the normal audited path.

### Emergency stop ON

Treat this as intentional deny-by-default. Investigate why the stop was enabled before turning it off. Do not bypass it through direct database writes.

### Provider authorization/recovery

For YouTube, a provider reauthorization requirement is distinct from Growth OS session expiry. Human OAuth authorization must use the supported reconnect path; credentials, tokens and OAuth codes must never be pasted into chat, logs or documentation.

## 4. Publication recovery

- `confirmed`: provider-side confirmation exists; no resend.
- `needs_user_action`: reconciliation is required; do not assume success or failure.
- retry/dead-letter states: respect bounded retry policy and operator review.
- cancelled/superseded intents must not be executed.

A real external publication acceptance test requires explicit authorization for the concrete account and content version.

## 5. Evidence and observability rules

- Log safe operation names and status classes, never secrets or provider response bodies containing credentials.
- Keep evidence refs, publication intent refs and automation result refs in the audit chain.
- Distinguish test/browser fixtures from factual production evidence.
- Record exact GitHub SHA, CI run, Railway deployment and applicable migrations for freeze evidence.

## 6. Release gate

Before declaring Phase 9 or the project frozen:

1. exact-head CI must pass;
2. Copilot must pass unit/type/build/browser gates;
3. Analytics quality alerts must be visible in the UI;
4. Autopilot approval/execution and emergency-stop boundaries must remain green;
5. production deployment/health must match the accepted runtime SHA;
6. external provider gates must be proven with real provider behavior or explicitly documented as external limitations;
7. final consolidated adversarial review must run on the exact final state.
