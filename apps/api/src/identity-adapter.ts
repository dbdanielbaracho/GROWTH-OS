import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { isIP } from "node:net";
import type { FastifyReply, FastifyRequest } from "fastify";
import * as argon2 from "argon2";
import { z } from "zod";
import { env } from "./config.js";
import { db } from "./db.js";
import { withUserTransaction } from "./tenant-db.js";
import {
  getActiveWorkspaceForUser,
  listActiveWorkspacesForUser,
  type WorkspaceSummary
} from "./workspaces.js";

export const SignInSchema = z.object({
  email: z.string().trim().min(3).max(320).email(),
  password: z.string().min(1).max(1024)
});

export const WorkspaceSelectionSchema = z.object({
  workspaceId: z.string().uuid()
});

export class IdentityAuthenticationError extends Error {}
export class IdentityRateLimitedError extends Error {}
export class IdentityCsrfError extends Error {}
export class IdentityWorkspaceRequiredError extends Error {}

export type ResolvedIdentitySession = {
  sessionId: string;
  userId: string;
  amr: string[];
  absoluteExpiresAt: string;
  idleExpiresAt: string;
};

export type IdentitySessionView = {
  session: ResolvedIdentitySession;
  workspaces: WorkspaceSummary[];
  selectedWorkspace: WorkspaceSummary | null;
  csrfToken: string;
};

type PasswordLookup = {
  user_id: string;
  auth_identity_id: string;
  password_hash: string;
  hash_algorithm: string;
  hash_version: number;
  must_change: boolean;
  user_status: string;
  email_verified_at: string | null;
};

type SessionRow = {
  session_id: string;
  user_id: string;
  amr: string[];
  absolute_expires_at: string;
  idle_expires_at: string;
};

type LoginAttemptReservation = {
  attempt_id: string | null;
  email_failures: number;
  ip_failures: number;
  blocked: boolean;
};

const production = env.NODE_ENV === "production";
export const SESSION_COOKIE_NAME = production ? "__Host-growth_session" : "growth_session";
export const WORKSPACE_COOKIE_NAME = production ? "__Host-growth_workspace" : "growth_workspace";

const SESSION_TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);
const appOrigin = new URL(env.APP_ORIGIN).origin;

function sessionCookieOptions(expires?: Date) {
  return {
    path: "/",
    httpOnly: true,
    secure: production,
    sameSite: "lax" as const,
    ...(expires ? { expires } : {})
  };
}

function hashToken(rawToken: string): string {
  return createHash("sha256").update(rawToken, "utf8").digest("hex");
}

function csrfForSession(sessionId: string): string {
  return createHmac("sha256", env.CSRF_SECRET).update(sessionId, "utf8").digest("base64url");
}

function safeStringEqual(left: string, right: string): boolean {
  const a = Buffer.from(left, "utf8");
  const b = Buffer.from(right, "utf8");
  return a.length === b.length && timingSafeEqual(a, b);
}

function headerValue(value: string | string[] | undefined): string | null {
  if (typeof value === "string") return value;
  if (Array.isArray(value) && value.length === 1) return value[0] ?? null;
  return null;
}

export function requestClientIp(request: FastifyRequest): string | null {
  const railwayIp = headerValue(request.headers["x-real-ip"]);
  if (railwayIp && isIP(railwayIp)) return railwayIp;
  return request.ip && isIP(request.ip) ? request.ip : null;
}

export function assertTrustedOrigin(request: FastifyRequest): void {
  const origin = headerValue(request.headers.origin);
  if (!origin) throw new IdentityCsrfError("missing_origin");

  let normalized: string;
  try {
    normalized = new URL(origin).origin;
  } catch {
    throw new IdentityCsrfError("invalid_origin");
  }

  if (normalized !== appOrigin) throw new IdentityCsrfError("untrusted_origin");
}

export function assertSessionCsrf(request: FastifyRequest, sessionId: string): void {
  if (SAFE_METHODS.has(request.method.toUpperCase())) return;
  assertTrustedOrigin(request);

  const supplied = headerValue(request.headers["x-csrf-token"]);
  const expected = csrfForSession(sessionId);
  if (!supplied || !safeStringEqual(supplied, expected)) {
    throw new IdentityCsrfError("invalid_csrf_token");
  }
}

function currentArgon2Options() {
  return {
    type: argon2.argon2id as 2,
    version: 0x13,
    memoryCost: env.ARGON2_MEMORY_COST_KIB,
    timeCost: env.ARGON2_TIME_COST,
    parallelism: env.ARGON2_PARALLELISM,
    hashLength: env.ARGON2_HASH_LENGTH
  };
}

let dummyHashPromise: Promise<string> | null = null;
function dummyPasswordHash(): Promise<string> {
  dummyHashPromise ??= argon2.hash(randomBytes(32), currentArgon2Options());
  return dummyHashPromise;
}

async function beginLoginAttempt(
  email: string,
  ip: string | null,
  userAgent: string | null
): Promise<LoginAttemptReservation> {
  const result = await db.query<LoginAttemptReservation>(
    `select *
       from growth.identity_begin_login_attempt(
         $1,
         $2::inet,
         $3,
         ($4::text || ' seconds')::interval,
         $5,
         $6
       )`,
    [
      email,
      ip,
      userAgent,
      env.LOGIN_RATE_WINDOW_SECONDS,
      env.LOGIN_MAX_EMAIL_FAILURES,
      env.LOGIN_MAX_IP_FAILURES
    ]
  );
  const reservation = result.rows[0];
  if (!reservation) throw new Error("identity_begin_login_attempt returned no row");
  return reservation;
}

async function completeLoginAttempt(attemptId: string): Promise<void> {
  const result = await db.query<{ completed: boolean }>(
    "select growth.identity_complete_login_attempt($1) as completed",
    [attemptId]
  );
  if (result.rows[0]?.completed !== true) {
    throw new Error("identity_complete_login_attempt did not complete the reserved attempt");
  }
}

async function lookupPassword(email: string): Promise<PasswordLookup | null> {
  const result = await db.query<PasswordLookup>(
    "select * from growth.identity_lookup_password($1)",
    [email]
  );
  return result.rows[0] ?? null;
}


export function hashIdentityToken(rawToken: string): string {
  return hashToken(rawToken);
}

export async function hashIdentityPassword(password: string): Promise<string> {
  return argon2.hash(password, currentArgon2Options());
}

export async function signInWithPassword(
  emailInput: string,
  password: string,
  request: FastifyRequest
): Promise<IdentitySessionView & { rawSessionToken: string }> {
  if (production) assertTrustedOrigin(request);

  const email = emailInput.trim().toLowerCase();
  const ip = requestClientIp(request);
  const userAgent = headerValue(request.headers["user-agent"]);

  // Reserve the throttle slot before Argon2. The database serializes
  // concurrent reservations for the same email/IP, so a burst cannot race
  // through a separate check-then-record window.
  const reservation = await beginLoginAttempt(email, ip, userAgent);
  if (reservation.blocked || !reservation.attempt_id) {
    throw new IdentityRateLimitedError("signin_rate_limited");
  }

  const passwordRow = await lookupPassword(email);
  const hashForVerification = passwordRow?.password_hash ?? await dummyPasswordHash();

  let passwordMatches = false;
  try {
    passwordMatches = await argon2.verify(hashForVerification, password);
  } catch {
    passwordMatches = false;
  }

  const accepted = Boolean(
    passwordRow
    && passwordMatches
    && passwordRow.user_status === "active"
  );

  if (!accepted || !passwordRow) {
    // The reservation was inserted as succeeded=false and intentionally
    // remains a failure. No second write is required.
    throw new IdentityAuthenticationError("invalid_credentials");
  }

  // Convert only this exact reserved attempt to success. This clears the
  // email failure streak through the migration's "after last success" rule
  // and prevents successful logins from polluting the IP failure budget.
  await completeLoginAttempt(reservation.attempt_id);

  if (passwordRow.must_change) {
    throw new IdentityAuthenticationError("password_change_required");
  }

  const rawSessionToken = randomBytes(32).toString("base64url");
  const tokenHash = hashToken(rawSessionToken);
  const now = Date.now();
  const absoluteExpiresAt = new Date(now + env.SESSION_ABSOLUTE_TTL_SECONDS * 1000);
  const idleExpiresAt = new Date(now + env.SESSION_IDLE_TTL_SECONDS * 1000);

  const created = await withUserTransaction(passwordRow.user_id, async (client) => {
    if (argon2.needsRehash(passwordRow.password_hash, currentArgon2Options())) {
      const upgradedHash = await argon2.hash(password, currentArgon2Options());
      const upgraded = await client.query<{ upgraded: boolean }>(
        "select growth.identity_upgrade_password_hash($1,$2,$3) as upgraded",
        [passwordRow.auth_identity_id, upgradedHash, 19]
      );
      if (upgraded.rows[0]?.upgraded !== true) {
        throw new Error("password hash upgrade was not applied");
      }
    }

    const sessionResult = await client.query<{ session_id: string }>(
      `select growth.identity_create_session(
         $1,$2,$3::text[],$4,$5,$6::inet,$7
       ) as session_id`,
      [
        passwordRow.user_id,
        tokenHash,
        ["password"],
        absoluteExpiresAt.toISOString(),
        idleExpiresAt.toISOString(),
        ip,
        userAgent
      ]
    );
    const sessionId = sessionResult.rows[0]?.session_id;
    if (!sessionId) throw new Error("identity_create_session returned no session id");

    const workspaces = await listActiveWorkspacesForUser(client, passwordRow.user_id);
    return { sessionId, workspaces };
  });

  const selectedWorkspace = created.workspaces.length === 1 ? created.workspaces[0] ?? null : null;
  const session: ResolvedIdentitySession = {
    sessionId: created.sessionId,
    userId: passwordRow.user_id,
    amr: ["password"],
    absoluteExpiresAt: absoluteExpiresAt.toISOString(),
    idleExpiresAt: idleExpiresAt.toISOString()
  };

  return {
    rawSessionToken,
    session,
    workspaces: created.workspaces,
    selectedWorkspace,
    csrfToken: csrfForSession(created.sessionId)
  };
}

async function resolveSessionToken(rawToken: string): Promise<ResolvedIdentitySession> {
  if (!SESSION_TOKEN_PATTERN.test(rawToken)) {
    throw new IdentityAuthenticationError("invalid_session");
  }

  const tokenHash = hashToken(rawToken);
  const result = await db.query<SessionRow>(
    "select * from growth.identity_resolve_session($1)",
    [tokenHash]
  );
  const row = result.rows[0];
  if (!row) throw new IdentityAuthenticationError("invalid_session");

  return {
    sessionId: row.session_id,
    userId: row.user_id,
    amr: row.amr,
    absoluteExpiresAt: row.absolute_expires_at,
    idleExpiresAt: row.idle_expires_at
  };
}

function rawSessionFromRequest(request: FastifyRequest): string {
  const raw = request.cookies?.[SESSION_COOKIE_NAME];
  if (!raw) throw new IdentityAuthenticationError("missing_session");
  return raw;
}

function workspaceFromRequest(request: FastifyRequest): string | null {
  const raw = request.cookies?.[WORKSPACE_COOKIE_NAME];
  if (!raw) return null;
  return z.string().uuid().safeParse(raw).success ? raw : null;
}

function refreshedIdleExpiry(session: ResolvedIdentitySession, requestedIdle: string): string {
  const oldIdleMs = new Date(session.idleExpiresAt).getTime();
  const requestedMs = new Date(requestedIdle).getTime();
  const absoluteMs = new Date(session.absoluteExpiresAt).getTime();
  return new Date(Math.max(oldIdleMs, Math.min(requestedMs, absoluteMs))).toISOString();
}

async function touchSession(
  session: ResolvedIdentitySession,
  candidateWorkspaceId: string | null,
  requireWorkspace: boolean
): Promise<{
  workspaces: WorkspaceSummary[];
  selectedWorkspace: WorkspaceSummary | null;
  idleExpiresAt: string;
}> {
  return withUserTransaction(session.userId, async (client) => {
    let selectedWorkspace: WorkspaceSummary | null = null;

    if (candidateWorkspaceId) {
      selectedWorkspace = await getActiveWorkspaceForUser(client, session.userId, candidateWorkspaceId);
      if (!selectedWorkspace && requireWorkspace) {
        throw new IdentityAuthenticationError("workspace_not_authorized");
      }
    } else if (requireWorkspace) {
      throw new IdentityWorkspaceRequiredError("workspace_required");
    }

    const requestedIdle = new Date(Date.now() + env.SESSION_IDLE_TTL_SECONDS * 1000).toISOString();
    const touched = await client.query<{ touched: boolean }>(
      "select growth.identity_touch_session($1,$2) as touched",
      [session.sessionId, requestedIdle]
    );
    if (touched.rows[0]?.touched !== true) {
      throw new IdentityAuthenticationError("session_no_longer_valid");
    }

    const workspaces = await listActiveWorkspacesForUser(client, session.userId);
    return {
      workspaces,
      selectedWorkspace,
      idleExpiresAt: refreshedIdleExpiry(session, requestedIdle)
    };
  });
}

export async function resolveCookieSession(
  request: FastifyRequest,
  options: { requireWorkspace: boolean; enforceCsrf: boolean }
): Promise<IdentitySessionView> {
  const session = await resolveSessionToken(rawSessionFromRequest(request));
  if (options.enforceCsrf) assertSessionCsrf(request, session.sessionId);

  const workspaceId = workspaceFromRequest(request);
  const context = await touchSession(session, workspaceId, options.requireWorkspace);

  return {
    session: { ...session, idleExpiresAt: context.idleExpiresAt },
    workspaces: context.workspaces,
    selectedWorkspace: context.selectedWorkspace,
    csrfToken: csrfForSession(session.sessionId)
  };
}

export async function selectSessionWorkspace(
  request: FastifyRequest,
  workspaceId: string
): Promise<IdentitySessionView> {
  const session = await resolveSessionToken(rawSessionFromRequest(request));
  assertSessionCsrf(request, session.sessionId);

  const context = await withUserTransaction(session.userId, async (client) => {
    const selectedWorkspace = await getActiveWorkspaceForUser(client, session.userId, workspaceId);
    if (!selectedWorkspace) throw new IdentityAuthenticationError("workspace_not_authorized");

    const requestedIdle = new Date(Date.now() + env.SESSION_IDLE_TTL_SECONDS * 1000).toISOString();
    const touched = await client.query<{ touched: boolean }>(
      "select growth.identity_touch_session($1,$2) as touched",
      [session.sessionId, requestedIdle]
    );
    if (touched.rows[0]?.touched !== true) {
      throw new IdentityAuthenticationError("session_no_longer_valid");
    }

    const workspaces = await listActiveWorkspacesForUser(client, session.userId);
    return {
      selectedWorkspace,
      workspaces,
      idleExpiresAt: refreshedIdleExpiry(session, requestedIdle)
    };
  });

  return {
    session: { ...session, idleExpiresAt: context.idleExpiresAt },
    workspaces: context.workspaces,
    selectedWorkspace: context.selectedWorkspace,
    csrfToken: csrfForSession(session.sessionId)
  };
}

export async function revokeCurrentSession(request: FastifyRequest): Promise<void> {
  const session = await resolveSessionToken(rawSessionFromRequest(request));
  assertSessionCsrf(request, session.sessionId);

  await withUserTransaction(session.userId, async (client) => {
    const result = await client.query<{ revoked: boolean }>(
      "select growth.identity_revoke_session($1,'logout') as revoked",
      [session.sessionId]
    );
    if (result.rows[0]?.revoked !== true) {
      throw new IdentityAuthenticationError("session_no_longer_valid");
    }
  });
}

export async function revokeAllSessions(request: FastifyRequest): Promise<number> {
  const session = await resolveSessionToken(rawSessionFromRequest(request));
  assertSessionCsrf(request, session.sessionId);

  return withUserTransaction(session.userId, async (client) => {
    const result = await client.query<{ revoked_count: number }>(
      "select growth.identity_revoke_all_sessions() as revoked_count"
    );
    return result.rows[0]?.revoked_count ?? 0;
  });
}

export function setSessionCookies(
  reply: FastifyReply,
  rawSessionToken: string,
  absoluteExpiresAt: string,
  selectedWorkspaceId: string | null
): void {
  const expires = new Date(absoluteExpiresAt);
  reply.setCookie(SESSION_COOKIE_NAME, rawSessionToken, sessionCookieOptions(expires));

  if (selectedWorkspaceId) {
    reply.setCookie(WORKSPACE_COOKIE_NAME, selectedWorkspaceId, sessionCookieOptions(expires));
  } else {
    reply.clearCookie(WORKSPACE_COOKIE_NAME, sessionCookieOptions());
  }
}

export function setWorkspaceCookie(
  reply: FastifyReply,
  workspaceId: string,
  absoluteExpiresAt: string
): void {
  reply.setCookie(
    WORKSPACE_COOKIE_NAME,
    workspaceId,
    sessionCookieOptions(new Date(absoluteExpiresAt))
  );
}

export function clearIdentityCookies(reply: FastifyReply): void {
  reply.clearCookie(SESSION_COOKIE_NAME, sessionCookieOptions());
  reply.clearCookie(WORKSPACE_COOKIE_NAME, sessionCookieOptions());
}
