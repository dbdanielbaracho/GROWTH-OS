# Growth OS — Identity, Tenancy and Application Shell — Technical Design v1 (Bloco 1a)

Status: DESIGN ONLY — no migration written, no database altered.
Source of truth: `docs/canonical/Growth_OS_Projeto_Conceitual_v1.4.1_CONGELADO_para_Claude.docx`
(Section 3, 10, 11, 21, 28) and `docs/canonical/Growth_OS_Especificacao_Tecnica_v0.4.1_CONGELADA.docx`
(Section 7 "Identity, Tenancy and Authorization", Section 9 "Security Baseline", Section 33 backlog).
This document proposes the **future migration `006`**. It does not modify any frozen document.
Any point where implementation reality appears to conflict with the frozen baseline is marked
**DIVERGENCE** below rather than silently resolved.

---

## 1. Identity and Authentication

### 1.1 Global users, multiple workspaces
`growth.users` already exists (`id uuid PK`, `email`, `status`, `created_at`) and remains the identity
anchor. Migration 006 proposes one explicit additive change to it: `email_verified_at timestamptz`.
A user is global to the Growth OS instance; workspace membership (`growth.memberships`, existing,
unchanged) is the many-to-many join that gives a user access to N workspaces. No new user table
is required — `growth.users` remains the single identity anchor across all workspaces.

### 1.2 Auth identities separated by provider
```sql
CREATE TABLE growth.auth_identities (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES growth.users(id),
  provider text NOT NULL CHECK (provider IN ('password','google','apple')),
  provider_subject text,              -- OAuth provider's stable user id; NULL for 'password'
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);
CREATE UNIQUE INDEX auth_identities_provider_subject_uq
  ON growth.auth_identities(provider, provider_subject)
  WHERE provider_subject IS NOT NULL AND revoked_at IS NULL;
CREATE UNIQUE INDEX auth_identities_one_active_password_uq
  ON growth.auth_identities(user_id)
  WHERE provider = 'password' AND revoked_at IS NULL;
```
One user may have multiple `auth_identities` rows (password + Google, for example). Each identity
is independently revocable without touching the others — disconnecting Google does not remove the
password identity, and vice versa.

OAuth sign-in must validate issuer, audience, expiration, nonce and PKCE before trusting
`provider_subject`. A provider email is profile data, not an identity key: the system MUST NOT
silently link an OAuth identity to an existing password account merely because the email strings
match. Linking requires an already-authenticated session or a separate, verified account-linking
ceremony, preventing provider-email confusion from becoming account takeover.

### 1.3 Password credential separate from OAuth identities
```sql
CREATE TABLE growth.password_credentials (
  auth_identity_id uuid PRIMARY KEY REFERENCES growth.auth_identities(id),
  password_hash text NOT NULL,        -- full PHC string, includes algorithm+params+salt+hash
  hash_algorithm text NOT NULL DEFAULT 'argon2id',
  hash_version smallint NOT NULL,      -- Argon2 'v' parameter (currently 19/0x13)
  must_change boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
```
Kept as a separate 1:1 table (not columns on `auth_identities`) so that OAuth-only identities never
carry password columns at all, and so password rotation touches a narrower table.

### 1.4 Argon2id parameters
Stored as explicit, versioned application configuration (not hard-coded), so parameters can be
raised over time without a schema change — the PHC-format `password_hash` string self-describes
which parameters produced it:
- Algorithm: `argon2id` (resistant to both GPU cracking and side-channel attacks; the OWASP-recommended
  variant for password hashing as of this design).
- Baseline starting parameters (config-versioned): memory cost 19 MiB (`m=19456`), iterations `t=2`,
  parallelism `p=1`. This profile was verified on 2026-09-02 against the primary OWASP Password
  Storage Cheat Sheet, which lists it as one of the recommended equivalent Argon2id configurations:
  <https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#argon2id>.
  It is a minimum, not a performance target: implementation must benchmark the deployed Railway
  runtime and may select a stronger listed profile while keeping legitimate verification below the
  agreed latency budget.
- Verification always re-derives from the stored PHC string's own embedded parameters, never from
  the application's current default — this is what allows raising defaults without invalidating
  existing hashes. When a login succeeds against an outdated parameter set, the application already
  has the plaintext password in memory and transparently rehashes it in that same successful flow.
  `must_change` is reserved for an explicit administrative/compromise response that requires the user
  to select a new password; it is not used for ordinary work-factor upgrades.

### 1.5 Email verification
```sql
CREATE TABLE growth.email_verifications (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES growth.users(id),
  email text NOT NULL,                -- snapshot at issuance time; supports email-change flows
  token_hash text NOT NULL,           -- sha256(token); raw token never stored
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz
);
CREATE UNIQUE INDEX email_verifications_token_hash_uq ON growth.email_verifications(token_hash);
CREATE INDEX email_verifications_user_open_idx
  ON growth.email_verifications(user_id) WHERE consumed_at IS NULL;
```
`growth.users` gains `email_verified_at timestamptz` (nullable). Unverified accounts may sign in
(so a slow verification email does not block first use) but MUST be restricted from workspace-owner
actions. Invitations may be issued to an email before an account exists, but an account cannot accept
the invitation or gain membership until that same normalized email is verified. The exact restriction
matrix is part of Section 8's endpoint/authorization matrix, not decided ad hoc.

### 1.6 Password recovery
```sql
CREATE TABLE growth.password_resets (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES growth.users(id),
  token_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  requested_ip inet,
  requested_user_agent text
);
CREATE UNIQUE INDEX password_resets_token_hash_uq ON growth.password_resets(token_hash);
```
Successful password reset MUST, in the same transaction: consume the reset token, update
`password_credentials`, and revoke every existing session for that user (Section 2.4) — password
reset is a full-account security event, not a narrow credential update.

### 1.7 MFA-ready structure
```sql
CREATE TABLE growth.mfa_factors (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES growth.users(id),
  factor_type text NOT NULL CHECK (factor_type IN ('totp','webauthn')),
  label text,
  secret_encrypted bytea,             -- TOTP only; envelope-encrypted
  credential_id bytea,                -- WebAuthn only; provider credential identifier
  public_key bytea,                   -- WebAuthn only
  sign_count bigint,                  -- WebAuthn replay/cloning signal
  created_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,           -- NULL until the user proves possession once
  revoked_at timestamptz,
  CHECK (
    (factor_type = 'totp' AND secret_encrypted IS NOT NULL AND credential_id IS NULL AND public_key IS NULL)
    OR
    (factor_type = 'webauthn' AND secret_encrypted IS NULL AND credential_id IS NOT NULL AND public_key IS NOT NULL)
  )
);
CREATE UNIQUE INDEX mfa_factors_webauthn_credential_uq
  ON growth.mfa_factors(credential_id) WHERE credential_id IS NOT NULL AND revoked_at IS NULL;

CREATE TABLE growth.mfa_recovery_codes (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES growth.users(id),
  code_hash text NOT NULL,             -- high-entropy code; raw value shown once and never stored
  created_at timestamptz NOT NULL DEFAULT now(),
  consumed_at timestamptz
);
CREATE UNIQUE INDEX mfa_recovery_codes_hash_uq ON growth.mfa_recovery_codes(code_hash);
```
No MFA enforcement logic ships in migration 006 — the table exists so that later MFA work is an
additive feature, not a migration that touches `users` or `auth_identities` again. `growth.sessions`
(Section 2) already carries an `amr` (authentication methods reference) array field for this reason.

---

## 2. Sessions

### 2.1 Opaque server-side session, not a JWT
```sql
CREATE TABLE growth.sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES growth.users(id),
  session_token_hash text NOT NULL,   -- sha256(opaque random token); raw token never stored
  amr text[] NOT NULL DEFAULT '{}',   -- e.g. {'password'} or {'password','totp'}
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  absolute_expires_at timestamptz NOT NULL,   -- hard ceiling regardless of activity
  idle_expires_at timestamptz NOT NULL,       -- rolling; extended on each authenticated request
  revoked_at timestamptz,
  revoked_reason text CHECK (revoked_reason IS NULL OR revoked_reason IN (
    'logout','logout_all','password_reset','admin_revoke','rotated'
  )),
  ip inet,
  user_agent text
);
CREATE UNIQUE INDEX sessions_token_hash_uq ON growth.sessions(session_token_hash);
CREATE INDEX sessions_user_active_idx
  ON growth.sessions(user_id) WHERE revoked_at IS NULL;
```
- The client holds only an opaque random token (≥256 bits of entropy) in an `HttpOnly`, `Secure`,
  `SameSite=Lax` (or `Strict` where the product flow tolerates it) cookie. The server never trusts
  a client-decodable claim for authorization — every request re-reads `growth.sessions` (or a cache
  fronting it) to resolve the current `user_id`.
- Only `session_token_hash` is stored, matching the invitation/email-verification/password-reset
  pattern already used in Sections 1.5–1.6 — raw bearer tokens never touch the database or logs.
- Cookie name uses the `__Host-` prefix when deployment topology permits it (host-only, `Secure`,
  `Path=/`, no `Domain` attribute). A new token is always issued after successful authentication,
  preventing session fixation.
- CSRF: `SameSite` is defense in depth, not the only control. Every browser state-changing endpoint
  (`POST`/`PATCH`/`DELETE`) MUST validate `Origin`/`Referer` and use a synchronizer or signed
  double-submit CSRF token. The implementation PR selects the exact compatible mechanism and proves
  it with a negative integration test.

### 2.2 Expiration
Both ceilings are enforced, independently:
- `absolute_expires_at`: set once at session creation (config-versioned duration, e.g. 30 days),
  never extended.
- `idle_expires_at`: extended on every authenticated request up to `absolute_expires_at`, never past it.
A session is valid only if `now() < absolute_expires_at AND now() < idle_expires_at AND revoked_at IS NULL`.

### 2.3 Rotation
On credential-strength events initiated by the current user (password change or MFA enrollment),
the current session's token is rotated: a new `sessions` row is inserted, the old row is marked
`revoked_at`/`revoked_reason = 'rotated'`, and the client's cookie is reissued. Membership and role
changes do not require token rotation because sessions carry no workspace or role claims; every
request re-resolves the current membership. An administrator may explicitly revoke all sessions for
a target user when the risk of the membership change warrants it.

### 2.4 Revocation and logout
- Individual logout: `UPDATE growth.sessions SET revoked_at = now(), revoked_reason = 'logout' WHERE id = :current_session_id`.
- Logout-all: `UPDATE growth.sessions SET revoked_at = now(), revoked_reason = 'logout_all' WHERE user_id = :user_id AND revoked_at IS NULL`.
- A session revoked mid-request: the authorization check re-reads `sessions` per request (no
  long-lived in-process cache of "is this session valid"), so a revoked session's *next* request is
  rejected. The *in-flight* request that raced the revocation is allowed to complete — Growth OS does
  not attempt to cancel already-running application code, consistent with how the DB-level RLS
  session variables in `tenant-db.ts` already behave per-transaction, not mid-transaction.

### 2.5 Never log tokens
`session_token_hash`, `token_hash` (invitations/verification/reset) and `password_hash` are the only
persisted forms; raw tokens exist only in the HTTP response body/redirect at issuance and in the
client's storage. Application logging middleware MUST redact `Authorization`, `Cookie`, and any
request/response body field named `token`, `password`, or matching `*_token` before it reaches any
log sink — this is a cross-cutting logging-middleware requirement, not a per-endpoint one.

---

## 3. Invitations

```sql
CREATE TABLE growth.invitations (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  invited_email text NOT NULL,        -- normalized: lower(trim(email))
  invited_role text NOT NULL CHECK (invited_role IN ('admin','editor','viewer')), -- never 'owner' via invitation
  can_publish boolean NOT NULL DEFAULT false,
  token_hash text NOT NULL,
  invited_by_user_id uuid NOT NULL REFERENCES growth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  status text NOT NULL CHECK (status IN ('pending','accepted','revoked','expired')) DEFAULT 'pending',
  accepted_at timestamptz,
  accepted_by_user_id uuid REFERENCES growth.users(id),
  revoked_at timestamptz,
  revoked_by_user_id uuid REFERENCES growth.users(id)
);
CREATE UNIQUE INDEX invitations_token_hash_uq ON growth.invitations(token_hash);
-- Exactly one PENDING invitation per (workspace, normalized email) — closes the "two concurrent
-- incompatible invitations" race at the constraint level, not in application code.
CREATE UNIQUE INDEX invitations_one_pending_per_workspace_email
  ON growth.invitations(workspace_id, invited_email) WHERE status = 'pending';
CREATE INDEX invitations_email_lookup_idx ON growth.invitations(invited_email) WHERE status = 'pending';
```

- **Hash-only token**: identical pattern to Sections 1.5/1.6/2.1.
- **Expiration + single-use**: `expires_at` plus the `status` state machine (`pending -> accepted |
  revoked | expired`) makes reuse structurally impossible once a row leaves `pending`.
- **Email normalization**: `lower(trim(email))` stored in `invited_email`, matching the existing
  `users_email_lower_uq` convention already in `001_initial_schema.sql`.
- **Concurrent-invite protection**: the partial unique index above is the enforcement mechanism —
  a second `INSERT` for the same `(workspace_id, invited_email)` while one is still `pending` fails
  the constraint. The accept flow additionally re-checks `status = 'pending' AND expires_at > now()`
  inside the same transaction as the atomic accept (below), so a resolved-but-not-yet-`expired`-flagged
  row cannot be accepted twice.
- **Expired-pending reconciliation**: before issuing a replacement invitation, the issuance
  transaction marks any prior `pending` row whose `expires_at <= now()` as `expired`, then inserts
  the new row. The partial unique index remains the final concurrent-writer arbiter; an expired row
  cannot permanently block a resend merely because no background reconciler ran.
- **Atomic accept**: a single narrow database operation that (a) locks the invitation row `FOR UPDATE`, (b)
  verifies `status = 'pending' AND expires_at > now()`, (c) marks it `accepted`, and (d) inserts (or
  reactivates a `revoked` row for) the corresponding `growth.memberships` row with `status = 'active'`
  — steps (c) and (d) commit together or not at all, so there is never a state where the invitation
  is `accepted` but no membership exists, or vice versa. The current `membership_write_guard` rejects
  a non-owner/non-admin inserting their own membership, so ordinary application SQL cannot implement
  this path. Migration 006 must add a narrowly scoped `SECURITY DEFINER` accept function (owned by a
  no-login helper role, fixed `search_path`, token hash + signed-in verified email as inputs) or an
  equivalently constrained trigger path that treats the locked valid invitation as the authorization
  grant. It may create only the workspace/user/role/capability recorded on that invitation and must
  still preserve all existing owner/admin and last-owner guards. Direct `INSERT` on memberships
  remains denied to the accepting user.
- **Auditable**: `invited_by_user_id`, `accepted_by_user_id`, `revoked_by_user_id` and every
  timestamp are retained on the row itself (append-effectively, since the state machine only moves
  forward); no separate audit table is required for invitations specifically, though the general
  audit log (Section 6.2) also records the same events for cross-entity querying.

---

## 4. Workspaces and Authorization

### 4.1 Atomic workspace + owner creation
```sql
-- Single transaction, single statement pair, no intermediate committed state:
BEGIN;
INSERT INTO growth.workspaces (id, name, default_market, default_language, default_timezone, status)
  VALUES (:workspace_id, :name, :market, :language, :timezone, 'active');
INSERT INTO growth.memberships (workspace_id, user_id, role, can_publish, status)
  VALUES (:workspace_id, :creator_user_id, 'owner', true, 'active');
COMMIT;
```
This mirrors the bootstrap pattern already proven in the RC7/RC9 test suite (`can_bootstrap_first_membership`)
— a workspace is never observable through any read path with zero owners, because the owner row is
created in the same transaction as the workspace row, not as a follow-up call.

### 4.2 Roles
`owner`, `admin`, `editor`, `viewer` — reusing the existing `growth.memberships.role` CHECK constraint
and the existing `membership_write_guard` trigger's authorization matrix unchanged:
- `owner`: full control, including granting/revoking `owner`/`admin`, cannot be the last remaining
  active owner removed (already enforced).
- `admin`: can manage `editor`/`viewer` memberships and workspace settings; cannot create or delete
  `owner`/`admin` memberships (already enforced by `membership_write_guard`).
- `editor`: content-domain read/write per Section 4.3's capability model.
- `viewer`: read-only.

### 4.3 Publish permission separable from editor
`growth.memberships.can_publish` already exists as a boolean independent of `role`. This design
keeps that separation explicit at the API-authorization layer too: an `editor` with
`can_publish = false` may create/edit content but any endpoint that transitions content into a
publish-triggering state MUST check `can_publish` in addition to `role`, not infer it from role.
This is a **capability check**, distinct from and additional to RBAC role checks — see 4.4.

### 4.4 RBAC + resource ownership + capability checks, deny-by-default
Three independent layers, all required, none substitutable for another:
1. **Authentication** — is there a valid, non-expired, non-revoked session? (Section 2)
2. **RBAC (role-based)** — does this principal's `role` in the *target workspace* permit this class
   of action? (existing `membership_write_guard` model for membership mutations; an equivalent
   deny-by-default check is required for every new identity/workspace-admin endpoint added in
   migration 006 — no endpoint may skip this check by omission.)
3. **Capability (attribute-based)** — even with the right role, does this specific action require an
   attribute the principal doesn't have (`can_publish`), or does the target resource's *own* state
   forbid it (e.g. workspace `status = 'suspended'`)? Capability checks are evaluated after RBAC,
   never instead of it.
Default posture: absence of an explicit ALLOW at every layer is a DENY. No endpoint may be
implemented as "allow unless a rule blocks it."

### 4.5 Workspace switching without trusting client-supplied `workspace_id`
Today, `tenant-db.ts`/`auth.ts` accept `workspaceId` as a raw client-supplied value (dev-only header).
Migration 006 changes this: the **session** (Section 2) carries no workspace binding by itself;
instead, every authenticated request that needs a workspace context MUST resolve
`(session.user_id, requested_workspace_id) -> membership` via `getCurrentMembership`-equivalent
lookup **before** calling `withTenantTransaction`, and reject with 403 if no active membership row
exists — the client may *request* a workspace, but the server, not the client, is what grants tenant
context, exactly as `workspaces.ts`'s existing join-based queries already assume but `auth.ts`
currently does not enforce upstream of them. "Current workspace" as a UX convenience (last-used
workspace) may be cached client-side, but every request still re-validates membership server-side —
it is a UX default, never an authorization shortcut.

### 4.6 No job or request without authorized context
Background workers (Section 5 of the roadmap, publishing/metrics workers) inherit this same rule:
a job record MUST carry `workspace_id` and the acting principal's provenance (`user_id` or a
system/service principal explicitly modeled — not "no principal"), and the worker MUST set
`app.workspace_id`/`app.user_id` via the same `set_config` mechanism `tenant-db.ts` already uses
before touching any RLS-protected table. A job that cannot resolve a valid authorized context fails
closed (moves to `FAILED`/`NEEDS_USER_ACTION`, never silently runs with elevated/ambiguous context).

---

## 5. Domain Separation from Platform Connections

- `growth.auth_identities` (Section 1.2) models **how a human signs in to Growth OS** — password,
  Google, Apple. It is not, and must never become, the storage location for a connected Instagram or
  YouTube account's OAuth token.
- Platform Connections (Instagram/YouTube OAuth, per Tech Spec v0.4.1 Section 8 "Platform Connection
  State Machine") already has the separate `growth.platform_connections` table in migration 001;
  its production connector behavior remains out of scope for migration 006. Credentials are encrypted
  at rest via envelope encryption/KMS per
  Tech Spec Section 23, with its own state machine (`UNCONNECTED -> AUTHORIZING -> CONNECTED -> ...`).
- No table introduced in this design stores a publishing-provider access/refresh token, scope grant,
  or provider account handle. `growth.auth_identities.provider_subject` stores only the *sign-in*
  provider's stable subject identifier (e.g. Google's `sub` claim) for the purpose of "log in with
  Google" — never a token, never a publishing-capable credential.

---

## 6. Operational Security

### 6.1 Login rate limiting, credential-stuffing protection, lockout
```sql
CREATE TABLE growth.login_attempts (
  id uuid PRIMARY KEY,
  email text NOT NULL,                 -- normalized; recorded even for unknown emails, to rate-limit enumeration
  user_id uuid REFERENCES growth.users(id),  -- NULL if email did not match any account
  succeeded boolean NOT NULL,
  ip inet,
  user_agent text,
  attempted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX login_attempts_email_recent_idx ON growth.login_attempts(email, attempted_at DESC);
CREATE INDEX login_attempts_ip_recent_idx ON growth.login_attempts(ip, attempted_at DESC);
```
- Rate limiting applies at two independent keys: per-email and per-IP, so an attacker rotating IPs
  against one email, or spraying one password across many emails from one IP, are both bounded.
- Lockout policy (exact thresholds are config-versioned policy, not hard-coded, mirroring the Tech
  Spec's own convention for evidence thresholds in Section 13): a sliding-window failure count per
  email triggers a temporary backoff/CAPTCHA-equivalent step-up rather than a permanent lock, to
  avoid a trivial denial-of-service against a known email. Successful login after lockout clears
  the counter.
- `login_attempts` is itself a bounded-retention table (rows older than the rate-limit window plus
  a short audit tail are purged by a scheduled job) — it is operational telemetry, not permanent audit,
  though a *summary* (account locked, at time X) is additionally written to the audit log (6.2) which
  has its own, longer retention.

### 6.2 Audit log
Migration 001 already defines the cross-domain `growth.audit_events` ledger (`workspace_id`,
`actor_user_id`, `event_type`, `resource_type`, `resource_id`, `correlation_id`, `metadata`,
`occurred_at`). Migration 006 MUST reuse that ledger rather than create a duplicate identity audit
table. Identity events use a versioned vocabulary such as `identity.login.succeeded.v1`,
`identity.login.failed.v1`, `identity.password_reset.completed.v1`,
`identity.invitation.accepted.v1`, `identity.membership.role_changed.v1` and
`identity.session.admin_revoked.v1`.

The migration must add the narrow policy/grant changes needed for account-level events where
`workspace_id IS NULL`, because the current tenant-only RLS policy does not make those rows visible.
Account events are visible only to the subject user through a redacted API view; workspace events
remain governed by active membership and tenant context. `app_runtime` receives INSERT plus the
minimum redacted read path, but no UPDATE or DELETE on audit rows. Raw normalized emails, tokens,
password material and session-token hashes are prohibited from `metadata`; unauthenticated login
failures use a non-reversible correlation value where cross-attempt grouping is required.

### 6.3 Deletion / tombstone lifecycle
The frozen lifecycle in Tech Spec Section 24 applies, but there is a material schema mismatch that
must not be hidden: `growth.users` is global while the existing `growth.deletion_requests` ledger
requires a non-null `workspace_id`. One workspace-scoped request therefore cannot safely represent
purging one user across every workspace membership and global credential/session row.

**DIVERGENCE / DEPENDENCY:** migration 006 does not add a destructive account-deletion endpoint.
Phase 1 may disable an account (`growth.users.status = 'disabled'`) and atomically revoke identities,
sessions and factors, but physical account purge remains blocked until a separate ADR/migration
defines the global-user deletion coordinator and reconciles the current database states
(`requested`, `tombstoned`, `purging`, `provider_pending`, `completed`, `failed`) with the frozen
`PURGED`/`FAILED_RETRYABLE` vocabulary. That later design must reuse the existing ledgers where
possible, preserve memberships/audit references as required, and include identity tables in the
purge manifest. No implementation may approximate global deletion by choosing an arbitrary
workspace or silently issuing independent requests without a single accountable coordinator.

### 6.4 Indexes, constraints, RLS per table
Every new table above gets, at DDL time (not deferred to a later migration):
- RLS `ENABLE` + `FORCE` where the table is workspace-scoped (`invitations`) — same posture as every
  existing `growth.*` tenant table. Existing `growth.audit_events` receives the explicit dual-scope
  policy described in Section 6.2.
- Account-scoped tables with a direct `user_id` (`auth_identities`, `sessions`,
  `email_verifications`, `password_resets`, `mfa_factors`) are constrained to the current user for
  the narrow self-service operations that are intentionally exposed. Sensitive columns are never
  returned by those APIs.
- The table without a direct subject key (`password_credentials`) resolves
  ownership through their parent relation inside policy/helper code; the design does not reference a
  nonexistent `user_id` column. `app_runtime` has no general SELECT for credential hashes, recovery
  code hashes or session token hashes. Password verification, signup, reset, token rotation and
  invitation acceptance execute through minimal `SECURITY DEFINER` functions owned by a dedicated
  no-login helper role with a fixed `search_path`, fully qualified objects and revoked `PUBLIC`
  execution. Signup is atomic across `users`, `auth_identities` and `password_credentials` and is
  the only unauthenticated path allowed to create those rows.
- Narrow helper functions (following the `growth_rls_helper` pattern established in migration 002)
  cover operations that must run before `app.user_id` can be set, because those operations are how
  the principal is determined. Each helper has an explicit grant and a negative test; there is no
  blanket owner-bypass API.
- `login_attempts` is the one exception with no per-row RLS predicate tied to a caller identity,
  since it must be writable by the unauthenticated login endpoint itself; it is protected instead by
  table-level grants restricted to the `app_runtime` role only, with no direct customer-facing read
  path at all (not even to `growth_test_harness` outside test provisioning).

### 6.5 No plaintext secrets or tokens
Enforced structurally, not by convention alone: every token-bearing table above stores only a hash
column (`token_hash`, `session_token_hash`, `password_hash`, `code_hash`), never a plaintext token
column. `mfa_factors.secret_encrypted` is explicitly typed `bytea` and named `_encrypted` to make a
future accidental plaintext write visually obvious in review.

---

## 7. Concurrency and Integrity

| Scenario | Mechanism |
|---|---|
| Simultaneous account/email creation | `users_email_lower_uq` (existing) is the atomic winner; losing `INSERT` returns a conflict, application maps it to "email already registered" without leaking whether it's mid-signup or fully active (avoids account-enumeration timing difference where feasible). |
| Two accepts of the same invitation | The atomic-accept transaction (Section 3) `SELECT ... FOR UPDATE` locks the invitation row; the second concurrent accept blocks until the first commits, then re-reads `status` and finds `'accepted'`, failing cleanly rather than creating a duplicate membership. Mirrors the `INSERT`-first idempotency pattern the Tech Spec already mandates for publication intents (Section 21/40.1) — same pattern, identity domain. |
| Concurrent role change | `growth.memberships` already has the trigger-enforced authorization matrix (`membership_write_guard`) plus row-level locking implicit in `UPDATE ... WHERE workspace_id = ? AND user_id = ?`; two concurrent role-change `UPDATE`s serialize normally at the row level — no new mechanism needed, this is exactly what the existing RC7/C2/C3/C4 concurrency test suite already proves for the underlying table. |
| Cannot remove the last owner | Already enforced by `membership_write_guard`'s last-active-owner guard (proven under real concurrency in tests C1–C4, `010_c1_membership_concurrency.sql` / `010_c2_c3_c4_membership_concurrency.sql`). Migration 006 introduces no new owner-removal path that bypasses this trigger — invitation acceptance can only ever *add* a membership, never remove an owner. |
| Session revoked during an active request | Per Section 2.4: the in-flight request is not forcibly cancelled (Growth OS does not implement mid-request kill), but the *next* request against that session is rejected because authorization re-reads `sessions.revoked_at` per request rather than caching validity for the process lifetime. |
| Atomic workspace + owner creation | Single transaction, Section 4.1 — no read-modify-write gap in which a workspace could be observed with zero owners. |

---

## 8. Contract and Test Plan

### 8.1 Threat model (summary)
Primary threats considered: credential stuffing / brute force against login; session token theft
(XSS, log leakage, network interception without TLS); CSRF against state-changing endpoints;
privilege escalation via role/membership mutation; invitation token guessing or replay; enumeration
of registered emails; tenant-isolation bypass via a forged/guessed `workspace_id`; stale-session
persistence after password compromise; background-job execution with ambiguous or absent tenant
context. Each threat maps to a specific control already specified in Sections 1–7 above (Argon2id +
rate limiting for stuffing; `HttpOnly`/`Secure` cookie + hash-only storage for token theft;
mandatory origin validation + CSRF token for browser requests; `membership_write_guard` +
deny-by-default RBAC for privilege
escalation; hashed single-use expiring tokens for invitations; normalized-timing responses where
feasible for enumeration; server-side membership resolution for tenant isolation; mandatory rotation
on credential-strength changes for stale sessions; fail-closed job authorization for background work).
**DIVERGENCE NOTE**: the frozen Tech Spec does not yet enumerate a standalone identity threat model
as a named artifact — this section is new engineering detail consistent with, but not previously
present in, v0.4.1. Recorded here as an addition, not a contradiction.

### 8.2 State diagrams

**Session**
```
(none) -> ACTIVE [on successful login]
ACTIVE -> ACTIVE [idle_expires_at extended on each authenticated request, bounded by absolute_expires_at]
ACTIVE -> EXPIRED [now() >= absolute_expires_at OR now() >= idle_expires_at]
ACTIVE -> REVOKED [logout | logout_all | password_reset | admin_revoke | rotated]
```

**Invitation**
```
(none) -> PENDING [invited by owner/admin, unique per (workspace, email)]
PENDING -> ACCEPTED [atomic accept: token valid + not expired -> membership created/reactivated]
PENDING -> REVOKED [inviter/admin cancels]
PENDING -> EXPIRED [expires_at passed; lazily reconciled on next read/accept attempt]
```

**Membership** (existing, unchanged — documented here for completeness of the identity picture)
```
(none) -> ACTIVE [bootstrap first owner | invitation accepted | owner/admin grants]
ACTIVE -> ACTIVE [role changed, subject to membership_write_guard matrix]
ACTIVE -> REVOKED [self-leave | owner/admin removes, subject to last-owner guard]
```

### 8.3 Proposed DDL for migration 006
The `CREATE TABLE`/`CREATE INDEX` statements in Sections 1.2–1.7, 2.1, 3 and 6.1 above are proposed
DDL sketches for review; Section 6.2 intentionally reuses `growth.audit_events`. Migration 006
additionally needs, not shown above for brevity: the explicit `ALTER TABLE growth.users ADD COLUMN
email_verified_at timestamptz`, RLS `ENABLE`/
`FORCE` + policy statements per Section 6.4, the `SECURITY DEFINER` login/invitation-lookup helper
functions (mirroring `002_rc9_security_policy_fix.sql`'s `growth_rls_helper`-owned function pattern),
grants for `app_runtime` scoped per Section 6.4/6.5, and an `invitation_write_guard` trigger
analogous in structure to `membership_write_guard` enforcing Section 3's concurrent-invite and
issuance rules plus the narrowly scoped invitation-accept function described in Section 3,
consistent with this project's
established principle that authorization-critical rules live in the database, not only in `apps/api`.
None of this is written yet — it is scoped here so the actual migration file can be reviewed against
this design before it exists.

### 8.4 Endpoint / authorization matrix (representative, not exhaustive)

| Endpoint | Auth required | RBAC | Capability check | Error on deny |
|---|---|---|---|---|
| `POST /v1/auth/signup` | none | — | rate-limited by IP | 429 on rate limit, 409 on duplicate email |
| `POST /v1/auth/signin` | none | — | rate-limited by email+IP, lockout-aware | 401 (generic, no user-enumeration detail), 429 |
| `POST /v1/auth/signout` | session | self only | — | 401 if no valid session |
| `POST /v1/auth/signout-all` | session | self only | — | 401 |
| `POST /v1/password-resets` | none | — | rate-limited | 202 always (no enumeration via response shape) |
| `POST /v1/password-resets/:token/complete` | none, token is the credential | — | token valid+unexpired+unconsumed | 400/410 on invalid/expired |
| `POST /v1/workspaces` | session | any verified user may create | — | 401/403 (unverified email) |
| `POST /v1/workspaces/:id/invitations` | session | owner may invite `admin`/`editor`/`viewer`; admin may invite only `editor`/`viewer` | target role not `owner`; inviter's own membership `active` | 403 |
| `POST /v1/invitations/:token/accept` | session (must be signed in as the invited identity) | — | invitation `pending`+unexpired, verified normalized email match | 403/410 |
| `PATCH /v1/workspaces/:id/memberships/:userId` | session | `membership_write_guard` matrix (existing) | last-owner guard (existing) | 403/409 |
| `DELETE /v1/workspaces/:id/memberships/:userId` | session | same | same | 403/409 |

Full matrix (every roadmap Phase-1 endpoint, not just this representative slice) is produced as part
of migration 006's own PR, once this design is approved — listing every endpoint here before the API
implementation exists would drift from the code faster than it could stay accurate.

### 8.5 Test plan
- **SQL tests** (new `db/tests/0XX_identity_*.sql`, following the existing numbering/README
  convention): constraint tests for every unique/check constraint above; RLS tests proving a user
  cannot read another user's `sessions`/`auth_identities`/`mfa_factors` rows; trigger tests for the
  new `invitation_write_guard`.
- **Integration tests** (new `apps/api/integration-tests/identity.integration.mts`, same pattern as
  `content-authoring.integration.mts`/`creative-production.integration.mts`): full signup -> verify
  -> signin -> create-workspace -> invite -> accept -> role-change -> logout-all flow against a real
  HTTP server and real Postgres, exactly as the existing integration tests already do.
- **Concurrency tests** (new `db/tests/0XX_identity_concurrency.sql`, real dual `psql` sessions,
  same methodology used throughout this project's RC7/RC9/Creative-Production concurrency proofs):
  the six scenarios in Section 7's table, each proven by physical execution, not by code inspection.
- **Security tests**: rate-limit/lockout behavior under scripted repeated failures; session-fixation
  resistance (a fresh token is issued at sign-in and rotates on credential-strength change);
  CSRF-token enforcement on a sampled state-changing endpoint.

### 8.6 Acceptance criteria
Migration 006 and its API are acceptable for freeze only when every item in Section 7's concurrency
table has a passing, physically-executed test; every RLS policy in Section 6.4 has a proven-negative
test (an unauthorized principal genuinely cannot read/write the protected row, not merely "the policy
exists"); the full signup-through-logout-all integration flow passes against `growth_os_test`; and
`app_runtime`'s final grant set for every new table has been reviewed against Section 6.5's
no-plaintext-secret rule by re-reading the actual grants, not by re-reading this document.

### 8.7 Rollout / rollback
Forward-only, matching this project's established migration discipline (no destructive `DOWN`
migrations in this codebase's history so far): migration 006 adds new tables, adds
`growth.users.email_verified_at`, and may replace or extend policies/functions only where this design
explicitly requires it. It does not drop existing tables or columns. If a defect is found after deployment to
`growth_os_test` or the primary database, the fix is a new forward migration (007+) correcting the
006 tables, never an edited or reverted 006 — consistent with the project's "no silent workaround,
version the correction" rule already applied throughout this conversation's Railway validation work.

---

## 9. Open Questions for Review

1. Session cookie `SameSite` policy (`Lax` vs `Strict`) has UX implications (cross-site invitation-link
   click-through) not yet resolved against the frozen concept's UX sections — flagged for product
   input, not a technical blocker.
2. Login-attempt lockout thresholds (Section 6.1) are deliberately left as configuration rather than
   fixed here — needs an owner to set initial values before migration 006 ships.
3. Session absolute/idle lifetimes and the throttling interval for `last_seen_at` writes must be set
   from product risk and measured Railway load before implementation freeze; the example 30-day
   absolute lifetime in Section 2.2 is not a frozen value.
4. Global-user deletion requires the ADR/schema decision recorded in Section 6.3 before any physical
   account-deletion endpoint can ship. It does not block signup/session/invitation implementation,
   but it is a blocking dependency for the later deletion workflow.

No other divergence from the frozen v1.4.1/v0.4.1 baseline was found while producing this design.
