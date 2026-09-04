# Growth OS — YouTube Connector Technical Design v0.3

Status: **IMPLEMENTATION CANDIDATE — ADVERSARIAL CORRECTIONS UNDER VALIDATION**  
Issue: #26  
Supersedes: `YOUTUBE_CONNECTOR_TECH_DESIGN_V0.2.md`  
Gate Zero authority: `GATE_ZERO_PROVIDER_SELECTION_V0.2_FROZEN.md`

## 1. Objective

Implement the first production-grade real-signal path:

`authorized YouTube channel -> OAuth -> Analytics/Data API -> provenance-preserving observations -> deterministic factual deltas -> evidence -> later insight/opportunity`

The connector must fit the final multi-provider architecture. No synthetic production observations or opportunities are allowed.

## 2. Security boundary

### Runtime role

`app_runtime` must not receive direct SELECT/INSERT/UPDATE/DELETE privileges on:

- `platform_connections`
- `provider_credentials`
- `social_accounts`
- `metric_observations`
- `capabilities`

It may invoke only narrowly reviewed `SECURITY DEFINER` functions that operate under the existing transaction-scoped `app.user_id` / `app.workspace_id` context.

### Existing RLS-helper boundary and the connector dependency

Migration 002 introduced `growth.workspace_row_visible(uuid)`, a narrow boolean `SECURITY DEFINER` predicate owned by `growth_rls_helper`, to support the `workspaces_member_select` RLS policy without recursive RLS evaluation.

Physical validation of the YouTube OAuth completion path exposed a dependency introduced by migration 010: `youtube_complete_authorization(...)`, owned by `growth_migrator`, traverses FORCE-RLS tables whose workspace policy invokes `workspace_row_visible(uuid)`. Without EXECUTE on that predicate the real callback path failed with `permission denied for function workspace_row_visible`.

Migration `012_youtube_rls_helper_execute.sql` therefore grants **only EXECUTE on `workspace_row_visible(uuid)` to `growth_migrator`**. It grants no table privilege, BYPASSRLS, role membership or ownership change. The predicate remains owned by `growth_rls_helper`, remains `SECURITY DEFINER`, and remains non-executable by PUBLIC.

### Managed-account prerequisite

OAuth is technical authorization, not a substitute for the existing legal/authority model. The YouTube authorization flow requires a pre-existing `managed_account` in the same workspace with:

`authority_status = contractually_granted`

The connector does not silently upgrade `pending` authority because a Google consent screen was completed.

### Credential storage

YouTube OAuth material is stored in `growth.provider_credentials`, separate from ordinary product reads. The legacy `platform_connections.credential_ciphertext` column remains unused by this connector.

Application encryption:

- AES-256-GCM;
- random nonce per encryption;
- authenticated additional data binds ciphertext to provider/workspace/connection;
- versioned key identifier;
- raw access/refresh tokens never logged.

Provider configuration is opt-in. If OAuth configuration or the 32-byte encryption key is missing, YouTube routes fail closed; the rest of Growth OS remains healthy.

Migration `011_youtube_connector_hardening.sql` adds a fail-closed check at the credential-write boundary. Even if an OAuth callback carries a previously valid authenticated state, credential insertion/update is rejected when the referenced user is no longer `active`, the workspace is no longer `active`, or membership/tenant context is no longer valid.

## 3. OAuth flow

Use Google's OAuth 2.0 web-server flow with the minimum read-only scopes required for the first slice:

- `https://www.googleapis.com/auth/youtube.readonly`
- `https://www.googleapis.com/auth/yt-analytics.readonly`

Authorization request:

- HTTPS redirect URI under the same Growth OS public origin;
- `access_type=offline`;
- `include_granted_scopes=true`;
- opaque authenticated/encrypted `state`;
- explicit consent when needed to obtain/refresh offline authorization.

The `state` payload binds:

- user ID;
- workspace ID;
- managed account ID;
- platform connection ID;
- expiry time;
- random nonce.

The callback validates/decrypts state before creating tenant context or persisting provider material. A successful callback is replay-resistant at the database boundary because the connection must still be in `authorizing` state; after successful persistence it becomes `connected`.

## 4. Initial provider calls

After OAuth code exchange:

1. Data API `channels.list` with `mine=true` identifies the authorized channel.
2. Zero channels fails closed.
3. More than one returned channel fails closed as `youtube_channel_selection_required`; the first slice never silently binds the wrong channel.
4. The connection becomes `connected` only after the channel identity and encrypted credential persist in one tenant transaction.
5. Daily Analytics sync uses `reports.query` with a bounded date range and channel-level core metrics.

Initial daily metrics:

- `views`
- `engagedViews`
- `estimatedMinutesWatched`
- `averageViewDuration`
- `likes`
- `comments`
- `shares`
- `subscribersGained`
- `subscribersLost`

No custom Growth score is produced by this first sync.

## 5. Provider-day temporal semantics

YouTube Analytics `day` values are **provider calendar days in Pacific Time**. Per the primary YouTube Analytics dimensions documentation, each date begins at 12:00AM Pacific time and ends at 11:59PM Pacific time; depending on daylight saving time, a provider day can therefore span 23, 24 or 25 hours.

The adapter must not treat a provider `YYYY-MM-DD` value as a UTC date.

Current v0.3 temporal contract:

- `source_timezone = America/Los_Angeles`;
- `observed_at` = actual UTC instant corresponding to the start of that provider day at 00:00 Pacific;
- `provider_effective_at` = same actual provider-day start instant;
- `source_range_start` = provider-day start instant;
- `source_range_end` = **exclusive** UTC instant corresponding to 00:00 Pacific on the next provider day;
- the conversion uses the IANA time-zone database through `Intl.DateTimeFormat`, not a hardcoded UTC-7/UTC-8 assumption;
- therefore DST transitions preserve 23/25-hour source ranges correctly.

Examples:

- `2026-09-01` (PDT) -> `[2026-09-01T07:00:00Z, 2026-09-02T07:00:00Z)`;
- `2026-12-01` (PST) -> `[2026-12-01T08:00:00Z, 2026-12-02T08:00:00Z)`;
- `2026-11-01` (DST fall-back) -> `[2026-11-01T07:00:00Z, 2026-11-02T08:00:00Z)`, a 25-hour provider day.

The sync lookback also uses Pacific calendar dates. The end date is the last **complete Pacific provider day**, not simply `UTC today - 1 day`. This prevents the connector from requesting the wrong provider date during the daily UTC/Pacific date boundary.

Because this changes persisted temporal semantics materially, the adapter/source identifiers advance to:

- adapter version: `youtube-v0.2`;
- source schema version: `youtube.analytics.daily.v2`.

The idempotency key already includes `source_schema_version`, so v1 and v2 temporal semantics cannot alias silently under the same logical execution.

## 6. Metric semantics

Every persisted observation records an explicit semantic version.

### `views`

YouTube's primary Help/Developer documentation states that beginning August 24, 2026, public views across all formats are counted from the moment playback begins. The first slice refuses to backfill before the provider day `2026-08-24` while historical comparability remains intentionally unresolved.

The source series is segmented at the **Pacific provider-day boundary** for `2026-08-24`, represented as `2026-08-24T07:00:00Z` for this report schema. This is a source-series boundary for the provider day, not a claim that Google globally flipped every system at that exact instant.

Semantic key:

`youtube.analytics.views.provider-day-2026-08-24.v2`

### `engagedViews`

The YouTube Analytics revision history of August 27, 2026 explicitly classifies **Engaged View as `Unchanged`** in the 2026 public-view alignment. Therefore v0.3 does **not** assign `2026-08-24` as a new semantic effective date to `engagedViews`.

Semantic key:

`youtube.analytics.engagedViews.stable.v2`

`semantic_effective_from = null` for this first slice rather than inventing an unsupported change date.

No claim is made about retroactive provider rewriting unless primary evidence establishes it.

## 7. Retention and refresh

The adapter records:

- `collected_at`;
- authorization class;
- retention deadline;
- refresh obligation;
- completeness;
- freshness;
- source/report range;
- provider/API and source-schema versions;
- response SHA-256 reference.

The first implementation does not expose a user-facing derived score/leaderboard/benchmark. The `derived_analytics` capability remains `disabled` and kill-switched until policy acceptance is documented and separately reviewed.

## 8. Idempotency / retry safety

The sync request requires a caller-persisted UUID `requestNonce`. For the first slice, that nonce is also stored as `collection_run_id` on every observation produced by that execution.

The observation idempotency key is derived from:

- provider;
- `requestNonce`;
- provider account/channel;
- reporting day;
- metric;
- metric semantic version;
- source schema version.

Claude's adversarial review found that migration 010's original conflict comparison could incorrectly alias materially different payloads, most clearly identical `raw_value` under different `unit` values. Migration `013_youtube_observation_idempotency_hardening.sql` corrects this forward-only without rewriting migration 010.

Under migration 013, one existing idempotency key is reusable only when the stable factual/source identity is NULL-safe identical, including:

- social account;
- provider content/account identity;
- metric;
- raw value;
- unit;
- observed/provider-effective timestamps;
- provider API/source schema versions;
- collection method;
- raw payload reference;
- adapter version;
- provider product/object type;
- metric semantic version/range;
- source range;
- authorization class;
- completeness;
- freshness;
- collection run.

`collected_at`, `retention_deadline` and `refresh_required_by` are intentionally excluded from factual identity because they are retry-time policy metadata; a true retry may recompute them without creating a new provider fact.

Behavior:

- same logical retry uses the same `requestNonce`;
- same key + identical stable factual/source payload -> existing observation UUID;
- same key + any material stable-field difference -> `youtube observation idempotency conflict`;
- a later intentional provider refresh/revision uses a new `requestNonce`, creating a new immutable observation instead of overwriting the prior fact;
- no PostgreSQL transaction remains open while waiting for Google network I/O;
- all observations for one returned report are persisted in one tenant transaction.

The first synchronous slice does not create a second database collection-run ledger. A durable run/job ledger belongs with scheduled/background ingestion.

## 9. API surface

- `GET /v1/integrations/youtube/status`
  - authenticated;
  - reports configuration/policy-gate state without exposing secrets.

- `POST /v1/integrations/youtube/authorize`
  - authenticated + CSRF protected;
  - input: `managedAccountId`;
  - creates an authorizing connection and returns the Google authorization URL.

- `GET /v1/integrations/youtube/callback`
  - validates opaque state;
  - exchanges code;
  - resolves the authorized channel;
  - persists encrypted OAuth material + `social_account`;
  - fails closed if user/workspace/membership authority became invalid during OAuth.

- `POST /v1/integrations/youtube/sync`
  - authenticated + CSRF protected;
  - input: `connectionId`, caller-persisted `requestNonce`, bounded lookback;
  - refreshes access token when necessary;
  - retrieves real Analytics data;
  - persists provenance-complete idempotent observations;
  - returns factual sync counts only, not a prohibited derived score.

## 10. Failure behavior

Fail closed for:

- missing/partial provider config;
- invalid/expired OAuth state;
- disabled user / suspended workspace / inactive membership at credential-write time;
- missing or revoked managed-account authority;
- absent or ambiguous channel identity;
- missing usable refresh token when refresh is required;
- Google 401/403 authorization failures;
- rate limit/provider transient failure;
- malformed Analytics response;
- invalid provider day/metric values;
- time-zone conversion failure;
- idempotency conflict;
- semantic window before the approved first-slice floor;
- missing required execution privilege on a pre-existing RLS helper predicate.

Provider errors are classified without placing tokens, authorization codes, cookies or ciphertext in logs.

## 11. Database migrations and gates

- `010_youtube_connector_foundation.sql`
  - provenance columns;
  - isolated `provider_credentials`;
  - five YouTube capability rows;
  - narrow authorization/credential/observation helpers.

- `011_youtube_connector_hardening.sql`
  - credential-write active-user/workspace/membership trigger;
  - no widening of `app_runtime` table privileges.

- `012_youtube_rls_helper_execute.sql`
  - narrow EXECUTE grant on `growth.workspace_row_visible(uuid)` to `growth_migrator`;
  - no direct table access/BYPASSRLS/role membership.

- `013_youtube_observation_idempotency_hardening.sql`
  - forward-only replacement of observation helper conflict comparison;
  - NULL-safe stable factual/source identity comparison.

- `029_youtube_connector_foundation.sql`
  - catalog privilege/function/capability/trigger gate.

- `030_youtube_rls_helper_execute.sql`
  - RLS-helper dependency / unchanged app-runtime boundaries.

- `031_youtube_observation_idempotency_hardening.sql`
  - gate that the hardened helper contains the required material identity fields and preserves privilege boundaries.

## 12. Validation contract

Before production promotion, isolated `growth_os_test` validation must prove:

1. correct database target;
2. canonical tenant fixture;
3. zero direct `app_runtime` privileges on protected connector tables;
4. OAuth authorization begin;
5. disabled user blocks credential persistence;
6. re-enabled user can complete authorization;
7. credential helper works without logging secret material;
8. identical factual retry returns same UUID;
9. changes to unit/completeness/freshness/raw payload reference/collection run cause idempotency conflict;
10. retry-time policy timestamp-only changes can still return the original UUID;
11. five YouTube capabilities remain present and derived analytics remains fail-closed;
12. rollback and exact zero-residue proof;
13. SQL gates 031/030/029/028/027 remain green;
14. `growth_migrator.rolbypassrls=false` and no `growth_migrator -> growth_rls_helper` membership;
15. unit tests prove real Pacific midnight conversion for PDT/PST and a DST 25-hour day;
16. unit tests prove lookback is based on the last complete Pacific day;
17. unit tests prove `engagedViews` has no fabricated `2026-08-24` effective date.

A catalog-only PASS is not sufficient if the real callback/observation path fails.

## 13. Next gate

Before production promotion:

1. migrations 010–013 and SQL gates 029–031 pass on isolated Postgres-Validation;
2. API integrity/typecheck/build/unit tests pass on the exact final SHA;
3. integration/physical validation proves credential isolation, active-context hardening, RLS-helper dependency, RLS boundaries and hardened idempotency behavior;
4. temporal unit tests prove Pacific provider-day semantics including DST and last-complete-day selection;
5. ChatGPT performs a final diff/evidence review;
6. Claude adversarially re-reviews the exact corrected final SHA and physical evidence;
7. only after Claude formal approval on that exact SHA may the PR be merged and migrations 010–013 be considered for production promotion;
8. real YouTube OAuth configuration remains a separate production gate.
