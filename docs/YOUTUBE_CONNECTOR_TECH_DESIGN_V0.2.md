# Growth OS — YouTube Connector Technical Design v0.2

Status: **IMPLEMENTATION CANDIDATE — PHYSICAL VALIDATION IN PROGRESS**  
Issue: #26  
Supersedes: `YOUTUBE_CONNECTOR_TECH_DESIGN_V0.1.md`  
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

### Existing RLS-helper boundary and the new connector dependency

Migration 002 introduced `growth.workspace_row_visible(uuid)`, a narrow boolean `SECURITY DEFINER` predicate owned by `growth_rls_helper`, to support the `workspaces_member_select` RLS policy without recursive RLS evaluation. At that time physical testing proved that `growth_migrator` did not need EXECUTE on this predicate, so only `app_runtime` received it.

Physical validation of the new YouTube OAuth completion path exposed a new dependency introduced by migration 010:

`youtube_complete_authorization(...)` is itself a `SECURITY DEFINER` function owned by `growth_migrator`. Its tenant-scoped writes/read checks traverse FORCE-RLS tables and, through the existing tenant/workspace policies, now require execution of `workspace_row_visible(uuid)`. Without that permission the real callback path fails with:

`permission denied for function workspace_row_visible`

Migration `012_youtube_rls_helper_execute.sql` therefore grants **only EXECUTE on `workspace_row_visible(uuid)` to `growth_migrator`**. It does not grant table privileges, BYPASSRLS, role membership, ownership, or any new `app_runtime` capability. The predicate remains owned by `growth_rls_helper`, remains `SECURITY DEFINER`, and remains non-executable by PUBLIC.

This is a forward-only adaptation of the existing privilege-separation model to a genuinely new code path; migrations 002/010/011 remain byte-identical.

### Managed-account prerequisite

OAuth is technical authorization, not a substitute for the existing legal/authority model. The YouTube authorization flow therefore requires a pre-existing `managed_account` in the same workspace with:

`authority_status = contractually_granted`

The connector does not silently upgrade `pending` authority because a Google consent screen was completed.

### Credential storage

New YouTube OAuth material is stored in `growth.provider_credentials`, separate from ordinary product reads. The legacy `platform_connections.credential_ciphertext` column remains unused by this connector.

Application encryption:

- AES-256-GCM
- random nonce per encryption
- authenticated additional data binds ciphertext to provider/workspace/connection
- versioned key identifier
- raw access/refresh tokens never logged

Provider configuration is opt-in. If OAuth configuration or the 32-byte encryption key is missing, YouTube routes fail closed; the rest of Growth OS remains healthy.

Migration `011_youtube_connector_hardening.sql` adds a second fail-closed check at the credential-write boundary. Even if an OAuth callback carries a previously valid authenticated state, credential insertion/update is rejected when the referenced user is no longer `active`, the workspace is no longer `active`, or membership/tenant context is no longer valid.

## 3. OAuth flow

Use Google's OAuth 2.0 web-server flow with the minimum read-only scopes required for the first slice:

- `https://www.googleapis.com/auth/youtube.readonly`
- `https://www.googleapis.com/auth/yt-analytics.readonly`

Authorization request:

- HTTPS redirect URI under the same Growth OS public origin
- `access_type=offline`
- `include_granted_scopes=true`
- opaque authenticated/encrypted `state`
- explicit consent when needed to obtain/refresh offline authorization

The `state` payload binds:

- user ID
- workspace ID
- managed account ID
- platform connection ID
- expiry time
- random nonce

The callback must validate/decrypt state before creating tenant context or persisting provider material. A successful callback is replay-resistant at the database boundary because the connection must still be in `authorizing` state; after successful persistence it becomes `connected`.

## 4. Initial provider calls

After OAuth code exchange:

1. Data API `channels.list` with `mine=true` identifies the authorized channel.
2. Zero channels fails closed.
3. More than one returned channel fails closed as `youtube_channel_selection_required`; the first slice never silently binds the wrong channel.
4. The connection becomes `connected` only after the channel identity and encrypted credential persist in one tenant transaction.
5. Daily Analytics sync uses `reports.query` with a bounded date range and core metrics appropriate to channel-level reporting.

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

YouTube Analytics `day` values represent Pacific-time calendar days. The generic observation keeps `source_timezone = America/Los_Angeles`; the first slice uses a stable per-day timestamp anchor while retaining the provider/date range and semantic-version fields needed by consumers. A later schema revision may add a provider-native `date` field if cross-provider temporal normalization proves it materially necessary.

## 5. Metric semantics

Every persisted observation records an explicit semantic version.

At minimum:

- `views` values collected under the post-2026-08-24 definition must not be treated as semantically interchangeable with an unknown/older definition.
- `engagedViews` is stored under its own semantic key.

No claim is made about retroactive provider rewriting unless primary evidence establishes it.

The first sync refuses to backfill before `2026-08-24`; that is a fail-closed implementation choice while historical comparability across the semantic break remains unproven.

## 6. Retention and refresh

The adapter records:

- `collected_at`
- authorization class
- retention deadline
- refresh obligation
- completeness
- freshness
- source/report range
- provider/API and source-schema versions
- response SHA-256 reference

The first implementation does not expose a user-facing derived score/leaderboard/benchmark. The `derived_analytics` capability remains `disabled` and kill-switched until policy acceptance is documented and separately reviewed.

## 7. Idempotency / retry safety

The sync request requires a caller-persisted UUID `requestNonce`. For the first slice, that nonce is also stored as `collection_run_id` on every observation produced by that execution.

The observation idempotency key is derived from:

- provider
- `requestNonce`
- provider account/channel
- reporting day
- metric
- metric semantic version
- source schema version

Behavior:

- retrying the same logical sync uses the **same `requestNonce`**;
- same nonce/key + same factual payload -> return the existing observation ID;
- same nonce/key + conflicting factual payload -> fail with an idempotency conflict;
- a later intentional provider refresh/revision uses a **new `requestNonce`**, so a new immutable observation can be recorded instead of overwriting the prior fact;
- the adapter never holds a PostgreSQL transaction open while waiting for Google network I/O;
- all observations for one returned report are persisted in one tenant transaction, so an insertion failure rolls that persistence unit back rather than leaving a partially written report.

The first synchronous slice does not create a second database collection-run ledger. A durable run/job ledger belongs with scheduled/background ingestion; adding it prematurely would duplicate the existing nonce/run identity without improving the synchronous correctness proof.

## 8. API surface candidate

- `GET /v1/integrations/youtube/status`
  - authenticated
  - reports connector configuration/policy-gate state without exposing secrets

- `POST /v1/integrations/youtube/authorize`
  - authenticated + CSRF protected
  - input: `managedAccountId`
  - creates an authorizing connection and returns the Google authorization URL

- `GET /v1/integrations/youtube/callback`
  - validates opaque state
  - exchanges code
  - resolves the authorized channel
  - persists encrypted OAuth material + `social_account`
  - fails closed if user/workspace/membership authority became invalid during OAuth

- `POST /v1/integrations/youtube/sync`
  - authenticated + CSRF protected
  - input: `connectionId`, caller-persisted `requestNonce`, bounded lookback
  - refreshes access token when necessary
  - retrieves real Analytics data
  - persists provenance-complete idempotent observations
  - returns factual sync counts only, not a prohibited derived score

## 9. Failure behavior

Fail closed for:

- missing/partial provider config
- invalid/expired OAuth state
- disabled user / suspended workspace / inactive membership at credential-write time
- missing or revoked managed-account authority
- absent or ambiguous channel identity
- missing usable refresh token when refresh is required
- Google 401/403 authorization failures
- rate limit/provider transient failure
- malformed Analytics response
- invalid provider day/metric values
- idempotency conflict
- semantic window before the approved first-slice floor
- missing required execution privilege on a pre-existing RLS helper predicate

Provider errors are classified without placing tokens, authorization codes, cookies or ciphertext in logs.

## 10. Database migrations and gates

- `010_youtube_connector_foundation.sql`
  - provenance columns
  - isolated `provider_credentials`
  - five YouTube capability rows
  - narrow authorization/credential/observation helpers
  - strict observation idempotency

- `011_youtube_connector_hardening.sql`
  - credential-write active-user/workspace/membership trigger only
  - no widening of `app_runtime` table privileges

- `012_youtube_rls_helper_execute.sql`
  - narrow EXECUTE grant on `growth.workspace_row_visible(uuid)` to `growth_migrator`
  - preserves `growth_rls_helper` ownership and PUBLIC denial
  - grants no direct table access and no BYPASSRLS

- `029_youtube_connector_foundation.sql`
  - catalog-only privilege/function/capability/trigger gate

- `030_youtube_rls_helper_execute.sql`
  - catalog-only proof of the new RLS-helper dependency and unchanged app-runtime boundaries

## 11. Physical validation contract

Before the connector can be sent for adversarial review, isolated `growth_os_test` validation must prove in one controlled path:

1. `current_database() = 'growth_os_test'`;
2. authorized managed-account fixture is created with exact canonical schema;
3. direct `app_runtime` table privileges remain zero on protected connector tables;
4. `youtube_begin_authorization` returns a connection ID;
5. disabling the user makes credential persistence fail closed;
6. re-enabling the user allows `youtube_complete_authorization` to return a social-account ID;
7. the credential read helper works without exposing ciphertext in logs;
8. identical observation retries return the same UUID;
9. same idempotency key with conflicting factual payload raises an idempotency conflict;
10. five YouTube capability rows remain present and derived analytics remains disabled/kill-switched;
11. the entire fixture transaction is rolled back;
12. exact post-rollback queries prove zero fixture residue;
13. SQL gates 030/029/028/027 and the existing security regressions remain green.

A catalog-only PASS is not sufficient if the real callback/observation path fails.

## 12. Next gate

Before production promotion:

1. migrations 010 + 011 + 012 and SQL gates 029 + 030 pass on isolated Postgres-Validation;
2. API integrity gate/typecheck/build/tests pass on the exact final SHA;
3. integration/physical validation proves credential isolation, active-context hardening, RLS-helper dependency, RLS boundaries and idempotent observation behavior without real provider secrets;
4. ChatGPT performs a final diff/evidence review;
5. Claude adversarially reviews the exact final SHA and the physical evidence;
6. only after Claude formal approval on that exact SHA may migrations 010/011/012 be considered for production and real YouTube OAuth configuration be added to Railway.
