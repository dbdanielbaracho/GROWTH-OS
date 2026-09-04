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
- issued/expiry time
- random nonce

The callback must validate/decrypt state before creating tenant context or persisting provider material.

## 4. Initial provider calls

After OAuth code exchange:

1. Data API `channels.list` with `mine=true` identifies the authorized channel.
2. The connection becomes `connected` only after the channel identity and encrypted credential persist in one tenant transaction.
3. Daily Analytics sync uses `reports.query` with a bounded date range and core metrics appropriate to channel-level reporting.

Initial daily metrics may include:

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

## 5. Metric semantics

Every persisted observation records an explicit semantic version.

At minimum:

- `views` values collected under the post-2026-08-24 definition must not be treated as semantically interchangeable with an unknown/older definition.
- `engagedViews` is stored under its own semantic key.

No claim is made about retroactive provider rewriting unless primary evidence establishes it.

## 6. Retention and refresh

The adapter records:

- `collected_at`
- authorization class
- retention deadline
- refresh obligation
- completeness
- freshness

The first implementation does not expose a user-facing derived score/leaderboard/benchmark. The `derived_analytics` capability remains disabled and kill-switched until policy acceptance is documented and separately reviewed.

## 7. Idempotency / retry safety

Each provider observation receives a deterministic idempotency key derived from the provider, channel, report day/range, metric, semantic version and source schema version.

Behavior:

- same key + same factual payload -> return the existing observation ID;
- same key + conflicting factual payload -> fail with an idempotency conflict;
- never silently overwrite a fact under the same idempotency key.

This preserves retry safety across provider timeouts, process crashes and repeated sync requests.

## 8. API surface candidate

- `POST /v1/integrations/youtube/authorize`
  - authenticated + CSRF protected
  - input: `managedAccountId`
  - creates an authorizing connection and returns the Google authorization URL

- `GET /v1/integrations/youtube/callback`
  - validates opaque state
  - exchanges code
  - resolves the authorized channel
  - persists encrypted OAuth material + `social_account`

- `POST /v1/integrations/youtube/sync`
  - authenticated + CSRF protected
  - input: `connectionId` and bounded lookback
  - refreshes access token when necessary
  - retrieves real Analytics data
  - persists provenance-complete idempotent observations
  - returns factual sync counts only, not a prohibited derived score

## 9. Failure behavior

Fail closed for:

- missing/partial provider config
- invalid/expired OAuth state
- missing or revoked managed-account authority
- absent channel identity
- missing usable refresh token when refresh is required
- Google 401/403 authorization failures
- rate limit/provider transient failure
- malformed Analytics response
- idempotency conflict
- unknown metric semantic mapping

Provider errors must be classified without placing tokens, authorization codes, cookies or ciphertext in logs.

## 10. Next gate

Before production promotion:

1. migration 010 + SQL gate 029 pass on isolated Postgres-Validation;
2. API typecheck/build/tests pass;
3. integration tests prove OAuth state/credential crypto and idempotent observation behavior without real secrets;
4. Claude adversarially reviews exact final SHA;
5. only after approval may migration 010 be considered for production and real YouTube OAuth configuration be added to Railway.
