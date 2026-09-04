# Growth OS — YouTube Connector Technical Design v0.1

Status: **IMPLEMENTATION CANDIDATE**  
Issue: #26  
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

Provider configuration is opt-in. If OAuth configuration or the 32-byte encryption key is missing, YouTube routes fail closed as `integration_not_configured`; the rest of Growth OS remains healthy.

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

- `029_youtube_connector_foundation.sql`
  - catalog-only privilege/function/capability/trigger gate

## 11. Next gate

Before production promotion:

1. migrations 010 + 011 + SQL gate 029 pass on isolated Postgres-Validation;
2. API integrity gate/typecheck/build/tests pass on the exact final SHA;
3. integration/physical validation proves credential isolation, active-context hardening, RLS boundaries and idempotent observation behavior without real provider secrets;
4. ChatGPT performs a final diff/evidence review;
5. Claude adversarially reviews the exact final SHA;
6. only after formal approval may migrations 010/011 be considered for production and real YouTube OAuth configuration be added to Railway.
