# Growth OS — Opportunity Radar v0.1

Status: implementation candidate for Issue #21; requires CI, isolated Postgres-Validation execution and Claude adversarial review before merge.

## Product purpose

Opportunity Radar is the first visible product slice of the Growth OS core promise:

> Find real organic-growth opportunities before they become obvious, explain why they are emerging, and show what to do next.

Version 0.1 intentionally implements only claims supported by the current database contract. It does not synthesize production opportunities, evidence, explanations or action prescriptions.

## Current source-of-truth contract

### Opportunity
Backed by `growth.opportunities`:
- workspace/account scope;
- market and platform;
- status;
- score;
- confidence JSON;
- ranking version;
- expiry and creation timestamps.

### Opportunity evidence
Backed by `growth.opportunity_evidence`:
- source class;
- evidence reference;
- observation timestamp.

### Related account intelligence
Backed by active `growth.insights` rows sharing the opportunity's exact `social_account_id`.

The API labels these as related insights, not as automatic causal proof for the opportunity. When an opportunity has no `social_account_id`, the API does not attach unrelated or general insights automatically.

Insight states remain faithful to the canonical database semantics:
- `confirmed_account` → Confirmed;
- `account_hypothesis` → Hypothesis;
- `general_practice` → General practice;
- `insufficient_signal` → Insufficient signal.

Insight evidence is backed by `growth.insight_evidence`.

## API

Existing:
- `GET /v1/opportunities` — active, non-expired ranked opportunity list.
- `GET /v1/insights` — active insights.

Added in v0.1:
- `GET /v1/opportunities/:id` — tenant-scoped, active/non-expired opportunity detail containing:
  - opportunity;
  - stored opportunity evidence;
  - exact-account related insights and their stored evidence.

Cross-tenant, expired and missing opportunity IDs return `not_found`; malformed UUIDs return `invalid_request`.

The list response adds `evidence_count` derived from stored evidence. Insight list/detail rows also expose stored `evidence_count`.

## Runtime security change

Migration `008_opportunity_radar_evidence_read.sql` adds only:
- `SELECT` on `growth.opportunity_evidence` to `app_runtime`;
- `SELECT` on `growth.insight_evidence` to `app_runtime`.

Both tables already use workspace RLS with FORCE RLS. No evidence write privilege is granted. `feed_cards` remains inaccessible to `app_runtime` in this slice.

Test `027_opportunity_radar_evidence_read.sql` locks this boundary.

## Web experience

The previous static conceptual web screen is replaced by a real API-backed Radar:
- ranked opportunity cards;
- stored confidence and score;
- real evidence count;
- opportunity detail;
- evidence/source rows;
- related insight states;
- explicit loading, error and empty states;
- mobile-responsive layout.

If there is no opportunity data, the UI displays no synthetic replacement.

If no approved action prescription is stored, the UI says so explicitly rather than asking an LLM to invent one.

Development identity headers are sent only in Vite DEV mode when `VITE_DEV_USER_ID` and `VITE_DEV_WORKSPACE_ID` are configured. A production build does not send these headers; production still requires the real identity adapter.

## Deferred by design

Version 0.1 does not yet implement:
- provider/social signal ingestion;
- opportunity generation;
- signal acceleration detection;
- trend migration;
- causal explanation engine;
- action prescription/timing window generation;
- outcome learning loop.

Those belong to the next Growth Intelligence Engine + connectors phase. Their absence must remain visible rather than being hidden by fake data.

## Required validation before merge

1. CI typecheck/build/unit tests green.
2. Clean rebuild of isolated `Postgres-Validation` from the exact branch SHA.
3. Migration 008 `COMMIT`.
4. Test 027 PASS.
5. Existing SQL/Identity/concurrency/Node regressions green.
6. `opportunity-radar.integration.mts` PASS with app_runtime + growth_migrator credentials.
7. Cross-tenant detail proof returns `not_found`.
8. Web/API behavior reviewed against the database contract.
9. Claude adversarial verdict on exact final SHA: `APPROVE`, `REQUEST CHANGES`, or `BLOCK`.

## Next phase after v0.1

Provider/signal ingestion → Growth Intelligence Engine → generated/ranked opportunities from real evidence → action recommendation → execution → outcome measurement → learning loop.
