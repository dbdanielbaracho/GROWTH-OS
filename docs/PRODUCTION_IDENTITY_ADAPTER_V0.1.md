# Growth OS — Production Identity Adapter v0.1

Status: implementation design for Issue #24.
Base: `main` at `4ccf30f63972d3f536fe74103ed78214cb873f2f`.

## Goal

Replace the deliberate production auth blocker with a server-side session adapter that uses the existing Identity v1 database API and never trusts caller-supplied user/workspace headers in production.

## Non-negotiable boundaries

- `app_runtime` continues to have no direct access to secret-bearing Identity tables.
- Session resolution uses `growth.identity_resolve_session(...)`.
- Raw session tokens are never stored or logged; PostgreSQL stores only SHA-256 hashes.
- `withTenantTransaction` remains the tenant execution boundary for product routes.
- Workspace context is never an authorization claim. A client-selected workspace is revalidated against an active membership on every authenticated request.
- Development header identity remains available only when `NODE_ENV !== 'production'`.

## Session transport

Production uses an opaque 256-bit random token in a host-only cookie:

`__Host-growth_session`

Required attributes:
- `Secure`
- `HttpOnly`
- `SameSite=Lax`
- `Path=/`
- no `Domain`

`SameSite=Lax` preserves normal navigation usability while reducing cross-site cookie sending. It is defense in depth, not the sole CSRF control.

The selected workspace is carried separately in:

`__Host-growth_workspace`

It is also host-only, `Secure`, `HttpOnly`, `SameSite=Lax`, `Path=/`. Its UUID value is untrusted input until membership validation succeeds.

## Session lifecycle

### Sign in

1. Normalize email.
2. Check distributed login throttle by normalized email and client IP.
3. Resolve password material via `identity_lookup_password`.
4. Verify password using Argon2id against the stored PHC string.
5. Record success/failure with `identity_record_login_attempt`.
6. On success, set only `app.user_id` in the DB transaction and create a new opaque session via `identity_create_session`.
7. If Argon2 parameters are outdated, transparently replace the password hash through the narrow Identity helper added by migration 009.
8. Return the session cookie and the user's active workspaces. If exactly one active workspace exists, select it automatically; otherwise the user chooses one explicitly.

Responses for unknown email and wrong password remain generic.

### Resolve request

1. Read `__Host-growth_session`.
2. SHA-256 the raw token.
3. Call `identity_resolve_session`.
4. Set `app.user_id` only.
5. Revalidate the selected workspace against an active membership.
6. Call `identity_touch_session` to update `last_seen_at` and roll idle expiry forward without passing the absolute expiry ceiling.
7. Only then create the `{ userId, workspaceId }` principal used by `withTenantTransaction`.

A missing, malformed, expired, revoked or disabled session fails closed with 401. A workspace without an active membership also fails closed.

### Workspace selection

A dedicated authenticated endpoint accepts a candidate workspace UUID, validates that the resolved session user has an active membership, then updates `__Host-growth_workspace`.

Changing this cookie alone never grants access because membership is rechecked on the next request.

### Logout

`POST /v1/auth/signout` revokes the current server-side session through `identity_revoke_session(..., 'logout')` and clears both cookies.

`POST /v1/auth/signout-all` uses `identity_revoke_all_sessions()` and clears both cookies.

Revocation takes effect on the next request because session validity is re-read from PostgreSQL per request.

## Idle-expiry divergence and migration 009

Identity v1 design requires `idle_expires_at` to roll forward on authenticated activity. The current `identity_resolve_session(text)` validates idle expiry but does not mutate `last_seen_at` or extend it.

Migration 009 adds `identity_touch_session(session_id, requested_idle_expires_at)` rather than rewriting migration 006. It:

- requires `app.user_id` to match the session owner;
- refuses revoked, absolute-expired, idle-expired or disabled-user sessions;
- updates `last_seen_at`;
- extends idle expiry only forward and never past `absolute_expires_at`;
- returns `false` rather than authorizing when the session is no longer valid.

This second check also closes the race between initial token resolution and principal creation.

## Login throttle

Migration 009 adds `identity_login_throttle_status(...)`, a read-only `SECURITY DEFINER` helper owned by `growth_identity_helper`.

The application supplies versioned policy values. The helper counts:
- failed attempts for the normalized email since the later of the sliding-window start or the most recent successful login for that email;
- failed attempts from the client IP in the sliding window.

No direct `SELECT` on `login_attempts` is granted to `app_runtime`.

The API returns 429 when either threshold is reached. Unknown emails are recorded too, preventing account-existence probing from bypassing throttling.

## Password-hash upgrade

Migration 009 adds `identity_upgrade_password_hash(...)` so a successful password login can transparently raise Argon2 parameters without granting table UPDATE privileges to `app_runtime`.

The helper requires the current `app.user_id` to own the active password identity and only accepts Argon2id PHC material.

## CSRF

Cookie authentication activates CSRF requirements for browser state-changing requests.

Production rules:
- exact `Origin` match against configured `APP_ORIGIN` for `POST`, `PUT`, `PATCH`, `DELETE`;
- authenticated unsafe requests additionally require `X-CSRF-Token`;
- the token is derived server-side as HMAC-SHA256 over the resolved session ID using `CSRF_SECRET` and returned by the authenticated session bootstrap response;
- comparison uses constant-time equality;
- the raw session token is never exposed to JavaScript.

Login is unauthenticated and therefore has no session-bound CSRF token yet; it still requires exact production Origin validation.

## Railway edge / client IP

In Railway production, use the edge-provided `X-Real-IP` header for login throttling. Do not enable a blanket `trustProxy=true` solely to obtain client IP.

## Logging

Production logging must not emit:
- `Cookie`;
- `Authorization`;
- `Set-Cookie`;
- password fields;
- raw session or CSRF credentials.

Fastify/Pino redaction is configured centrally, not route by route.

## Production topology assumption

The preferred deployment is same-site web + API (or a same-origin proxy path) so host-only cookies and `SameSite=Lax` work without cross-site cookie relaxation. If deployment topology later proves this impossible, that is a separate reviewed architecture change; do not switch to `SameSite=None` ad hoc.

## Required tests

- valid session + active membership succeeds;
- missing/malformed/unknown/expired/revoked session fails;
- disabled user fails;
- candidate workspace without active membership fails;
- workspace selection succeeds only for an active membership;
- forged workspace cookie does not authorize;
- dev identity headers cannot authenticate in production;
- idle expiry moves forward but never past absolute expiry;
- session revoked between resolve and touch fails;
- email/IP throttle blocks at configured thresholds;
- successful email login resets the email-side sliding failure sequence;
- wrong password and unknown email produce generic response shape;
- CSRF/Origin negatives fail on unsafe cookie-authenticated routes;
- logout and logout-all revoke server-side session state;
- pool reuse does not leak `app.user_id` or `app.workspace_id`;
- existing Identity, RLS, Opportunity Radar, Content and Creative gates remain green.
