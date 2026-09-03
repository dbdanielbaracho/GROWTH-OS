# Growth OS — Production Identity Adapter v0.2

Status: implementation architecture for Issue #24.
Supersedes: `docs/PRODUCTION_IDENTITY_ADAPTER_V0.1.md`.
Base lineage: Opportunity Radar merge `4ccf30f63972d3f536fe74103ed78214cb873f2f`.

## 1. Goal

Provide real production authentication for the Growth OS API and Opportunity Radar without trusting caller-supplied user/workspace headers, without widening direct access to Identity secret tables, and without weakening PostgreSQL tenant/RLS boundaries.

## 2. Production topology — one origin, not CORS

Production is intentionally deployed as one public HTTPS origin:

`browser -> Fastify -> built web + /v1/* API -> PostgreSQL`

The Fastify production process serves `apps/web/dist` and the API from the same host. The production web build mechanically ignores `VITE_API_BASE_URL` and requests relative `/v1/*` paths.

Consequences:
- `__Host-` cookies remain host-only;
- no cross-origin credentialed CORS path is required;
- `SameSite=Lax` remains viable without switching to `SameSite=None`;
- `APP_ORIGIN` is the exact public HTTPS origin and is the CSRF Origin allowlist;
- a production process without a readable `apps/web/dist/index.html` fails startup instead of silently creating an API-only second-origin topology.

The static document response carries a restrictive CSP, HSTS, `nosniff`, `DENY` framing, strict referrer policy, a restrictive permissions policy and same-origin opener/resource policies. The HTML shell is `no-store`; hashed `/assets/*` may be cached immutable.

## 3. Identity trust boundary

- `growth.users` remains the global identity anchor.
- `app_runtime` receives no direct table access to `growth.sessions`, `growth.login_attempts` or `growth.password_credentials`.
- Session lookup uses the approved Identity v1 database API.
- `withTenantTransaction` remains the tenant execution boundary.
- Production ignores `x-user-id` and `x-workspace-id` completely.
- Development header identity exists only when `NODE_ENV !== 'production'`.

## 4. Session transport

The client receives an opaque 256-bit random token in:

`__Host-growth_session`

Attributes:
- `Secure`
- `HttpOnly`
- `SameSite=Lax`
- `Path=/`
- no `Domain`

Only SHA-256 of the raw token is stored in PostgreSQL. Raw session tokens are neither persisted nor logged.

Workspace choice is stored separately in:

`__Host-growth_workspace`

The workspace UUID is never trusted as authorization. Every authenticated product request revalidates an active membership for the resolved session user.

## 5. Sign-in flow

1. Require exact trusted `Origin` in production.
2. Normalize the email.
3. Derive the client IP from Railway's edge `X-Real-IP` when it is a syntactically valid IP; otherwise use Fastify's direct request IP.
4. Atomically reserve a login-attempt slot in PostgreSQL **before Argon2 verification**.
5. If the email/IP budget is already exhausted, return 429 without spending Argon2 work.
6. Resolve password material through `identity_lookup_password`.
7. Verify the PHC string using Argon2id. Unknown email uses a strong dummy Argon2 hash so the response path remains generic.
8. A failed credential attempt leaves the reserved row as `succeeded=false`.
9. A genuine successful credential verification marks exactly that reservation `succeeded=true`.
10. If required, transparently upgrade Argon2 parameters through the narrow helper from migration 009.
11. Create a fresh server-side session through Identity v1.
12. Return active workspaces. Exactly one active workspace is auto-selected; otherwise explicit selection is required.

Unknown email and wrong password share the same public authentication failure shape.

## 6. Atomic throttle under concurrency

The earlier v0.1 design described a read-check followed later by attempt recording. That sequence could permit a concurrent burst to cross the threshold before individual failures became visible.

v0.2 closes that race with two migration-009 helpers:

### `identity_begin_login_attempt(...)`

- `SECURITY DEFINER`, owned by `growth_identity_helper`;
- takes transaction-scoped advisory locks for normalized email and IP in deterministic order;
- calculates current email/IP failure counts;
- if already blocked, returns no attempt ID and writes nothing;
- otherwise inserts one pessimistic `succeeded=false` reservation and returns its UUID.

### `identity_complete_login_attempt(attempt_id)`

- converts only the reserved attempt to `succeeded=true` after successful credential verification;
- no direct `UPDATE` privilege is granted on `login_attempts`.

This makes the throttle admission decision serializable for the same email/IP without keeping a database transaction open during expensive Argon2 computation.

The physical integration gate fires a burst of `2 * LOGIN_MAX_EMAIL_FAILURES` wrong-password requests concurrently and requires exactly the configured number to be processed as generic 401 attempts and the remainder to be rejected 429.

## 7. Session resolution and rolling idle expiry

For each authenticated request:
1. read the opaque session cookie;
2. hash it SHA-256;
3. call `identity_resolve_session`;
4. establish only `app.user_id` in a bootstrap transaction;
5. revalidate the candidate workspace against an active membership;
6. call `identity_touch_session`;
7. only then construct the `{ userId, workspaceId, sessionId }` principal used by tenant transactions.

`identity_touch_session`:
- requires `app.user_id` to match the session owner;
- rejects revoked/disabled/expired sessions;
- updates `last_seen_at`;
- only moves idle expiry forward;
- never crosses `absolute_expires_at`.

This is forward-only: migration 006 remains unchanged.

## 8. Workspace authorization

A valid session is not sufficient for tenant access. A workspace cookie or selection request is accepted only if an active membership exists for the resolved user and workspace.

Changing or forging the workspace cookie alone never grants data access. PostgreSQL RLS remains an independent enforcement layer after application validation.

A valid authenticated session with no selected workspace receives `workspace_required` on tenant product routes.

## 9. CSRF

Cookie-authenticated unsafe methods require:
- exact `Origin === APP_ORIGIN`;
- `X-CSRF-Token` equal to HMAC-SHA256(session ID, `CSRF_SECRET`).

The comparison is constant-time. The CSRF token is held in web memory only and can be reissued by `GET /v1/auth/session`; it is not stored in localStorage.

Signin has no pre-existing session-bound CSRF token, but still requires exact trusted Origin in production.

## 10. Logout and revocation

- `POST /v1/auth/signout` revokes the current server-side session and clears both cookies.
- `POST /v1/auth/signout-all` revokes every active session for the current user and clears both cookies.
- Session validity is re-read on each request, so revocation is effective on the next request.

## 11. Logging and secret handling

Central logging redaction covers:
- `Cookie`
- `Authorization`
- `X-CSRF-Token`
- response `Set-Cookie`
- password/token body fields

Raw session tokens never enter database rows, audit metadata or application log fields.

## 12. Migration 009 public boundary

Migration 009 adds only these narrow helpers:
- `identity_touch_session(uuid,timestamptz)`
- `identity_begin_login_attempt(text,inet,text,interval,integer,integer)`
- `identity_complete_login_attempt(uuid)`
- `identity_upgrade_password_hash(uuid,text,smallint)`

For each:
- owner = `growth_identity_helper`;
- `SECURITY DEFINER`;
- fixed safe search path;
- `PUBLIC EXECUTE` revoked;
- `app_runtime EXECUTE` granted.

No direct secret-table privilege is added.

## 13. Mandatory physical gates before merge

On a clean, isolated `Postgres-Validation` rebuild from the exact PR SHA:
- migrations through 009 COMMIT;
- `028_production_identity_adapter_support.sql` PASS;
- independent owner/ACL/direct-table privilege proof;
- all existing SQL, Identity, concurrency, Opportunity Radar, Content and Creative regressions green;
- production identity integration gate green under `NODE_ENV=production`;
- concurrent throttle burst proof green;
- production web-shell integration gate green after `npm run build`;
- production header identity rejected;
- malformed/unknown/expired/revoked sessions rejected;
- workspace forgery rejected;
- Origin/CSRF negatives rejected;
- rolling idle bounded by absolute expiry;
- logout/logout-all immediate on next request;
- pool context does not leak.

Claude must adversarially review the exact final SHA and return a formal `APPROVE`, `REQUEST CHANGES`, or `BLOCK` before merge. Production remains untouched until that gate is complete.
