import { createHash, randomBytes, randomUUID } from "node:crypto";
import assert from "node:assert/strict";
import * as argon2 from "argon2";
import { buildApp } from "../src/app.js";
import { db } from "../src/db.js";
import { withUserTransaction } from "../src/tenant-db.js";

if (process.env.NODE_ENV !== "production") {
  throw new Error("production-identity-adapter.integration.mts must run with NODE_ENV=production");
}

const APP_ORIGIN = process.env.APP_ORIGIN;
if (!APP_ORIGIN) throw new Error("APP_ORIGIN is required");

let failures = 0;
function check(name: string, ok: boolean, detail?: unknown) {
  if (ok) console.log(`PASS: ${name}`);
  else {
    failures++;
    console.error(`FAIL: ${name}`, detail ?? "");
  }
}

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function setCookies(response: { headers: Record<string, unknown> }): string[] {
  const raw = response.headers["set-cookie"];
  if (!raw) return [];
  return Array.isArray(raw) ? raw.map(String) : [String(raw)];
}

function cookieHeaderFromSetCookies(cookies: string[]): string {
  return cookies.map((value) => value.split(";", 1)[0]).join("; ");
}

function cookieValue(cookieHeader: string, name: string): string | null {
  const match = cookieHeader.split(/;\s*/).find((part) => part.startsWith(`${name}=`));
  return match ? match.slice(name.length + 1) : null;
}

function replaceCookie(cookieHeader: string, name: string, value: string): string {
  const parts = cookieHeader.split(/;\s*/).filter(Boolean);
  const next = parts.filter((part) => !part.startsWith(`${name}=`));
  next.push(`${name}=${value}`);
  return next.join("; ");
}

async function createVerifiedUser(email: string, password: string) {
  const passwordHash = await argon2.hash(password, {
    type: argon2.argon2id,
    memoryCost: 19_456,
    timeCost: 2,
    parallelism: 1,
    hashLength: 32
  });

  const signup = await db.query<{ user_id: string }>(
    "select growth.identity_signup($1,$2,19) as user_id",
    [email, passwordHash]
  );
  const userId = signup.rows[0]?.user_id;
  if (!userId) throw new Error("identity_signup returned no user id");

  const verificationToken = randomBytes(32).toString("base64url");
  const verificationHash = sha256(verificationToken);
  await withUserTransaction(userId, async (client) => {
    await client.query(
      "select growth.identity_issue_email_verification($1, now() + interval '15 minutes')",
      [verificationHash]
    );
  });
  await db.query("select growth.identity_consume_email_verification($1)", [verificationHash]);

  return { userId, email, password };
}

async function createWorkspace(userId: string, name: string): Promise<string> {
  return withUserTransaction(userId, async (client) => {
    const result = await client.query<{ workspace_id: string }>(
      "select growth.identity_create_workspace($1,'US','en','UTC') as workspace_id",
      [name]
    );
    const workspaceId = result.rows[0]?.workspace_id;
    if (!workspaceId) throw new Error("identity_create_workspace returned no workspace id");
    return workspaceId;
  });
}

const runTag = randomUUID().slice(0, 8);
const primary = await createVerifiedUser(`prod-auth-${runTag}@example.com`, `ProdAuth!${runTag}Aa9`);
const primaryWorkspace = await createWorkspace(primary.userId, `Primary ${runTag}`);
const victim = await createVerifiedUser(`prod-auth-victim-${runTag}@example.com`, `Victim!${runTag}Bb9`);
const victimWorkspace = await createWorkspace(victim.userId, `Victim ${runTag}`);
const noWorkspace = await createVerifiedUser(`prod-auth-noworkspace-${runTag}@example.com`, `NoWorkspace!${runTag}Cc9`);

const app = buildApp(false);

try {
  // Production header auth must be mechanically useless without a real session cookie.
  const headerOnly = await app.inject({
    method: "GET",
    url: "/v1/context",
    headers: {
      "x-user-id": primary.userId,
      "x-workspace-id": primaryWorkspace
    }
  });
  check("(1) production ignores development identity headers", headerOnly.statusCode === 401, headerOnly.body);

  const noOriginSignIn = await app.inject({
    method: "POST",
    url: "/v1/auth/signin",
    payload: { email: primary.email, password: primary.password }
  });
  check("(2) production signin rejects missing Origin", noOriginSignIn.statusCode === 403, noOriginSignIn.body);

  const badOriginSignIn = await app.inject({
    method: "POST",
    url: "/v1/auth/signin",
    headers: { origin: "https://evil.example" },
    payload: { email: primary.email, password: primary.password }
  });
  check("(3) production signin rejects untrusted Origin", badOriginSignIn.statusCode === 403, badOriginSignIn.body);

  const signInRes = await app.inject({
    method: "POST",
    url: "/v1/auth/signin",
    headers: { origin: APP_ORIGIN },
    payload: { email: primary.email, password: primary.password }
  });
  const signInBody = signInRes.json();
  check("(4) valid password signin succeeds", signInRes.statusCode === 200, signInRes.body);
  check("(5) sole active workspace is auto-selected", signInBody.selected_workspace?.id === primaryWorkspace, signInBody);
  check("(6) signin returns a session-bound CSRF token", typeof signInBody.csrf_token === "string" && signInBody.csrf_token.length >= 32, signInBody);

  const signInCookies = setCookies(signInRes);
  const sessionSetCookie = signInCookies.find((value) => value.startsWith("__Host-growth_session="));
  const workspaceSetCookie = signInCookies.find((value) => value.startsWith("__Host-growth_workspace="));
  check("(7) production issues __Host session cookie", Boolean(sessionSetCookie), signInCookies);
  check("(8) production issues __Host workspace cookie", Boolean(workspaceSetCookie), signInCookies);
  check("(9) session cookie is Secure HttpOnly SameSite=Lax Path=/ with no Domain",
    Boolean(sessionSetCookie)
      && /;\s*Secure(?:;|$)/i.test(sessionSetCookie!)
      && /;\s*HttpOnly(?:;|$)/i.test(sessionSetCookie!)
      && /;\s*SameSite=Lax(?:;|$)/i.test(sessionSetCookie!)
      && /;\s*Path=\/(?:;|$)/i.test(sessionSetCookie!)
      && !/;\s*Domain=/i.test(sessionSetCookie!),
    sessionSetCookie
  );

  const cookies = cookieHeaderFromSetCookies(signInCookies);
  const rawSession = cookieValue(cookies, "__Host-growth_session");
  assert(rawSession, "session cookie value is required for physical DB checks");
  const tokenHash = sha256(rawSession);

  const beforeTouch = await db.query<{
    session_id: string;
    absolute_expires_at: string;
    idle_expires_at: string;
  }>("select session_id, absolute_expires_at, idle_expires_at from growth.identity_resolve_session($1)", [tokenHash]);
  const beforeSession = beforeTouch.rows[0];
  assert(beforeSession, "session must resolve before touch test");

  await new Promise((resolve) => setTimeout(resolve, 1100));
  const contextRes = await app.inject({ method: "GET", url: "/v1/context", headers: { cookie: cookies } });
  check("(10) cookie-authenticated tenant request succeeds", contextRes.statusCode === 200, contextRes.body);
  check("(11) principal comes from session user/workspace", contextRes.json()?.context?.user_id === primary.userId && contextRes.json()?.context?.workspace_id === primaryWorkspace, contextRes.body);

  const afterTouch = await db.query<{
    session_id: string;
    absolute_expires_at: string;
    idle_expires_at: string;
  }>("select session_id, absolute_expires_at, idle_expires_at from growth.identity_resolve_session($1)", [tokenHash]);
  const afterSession = afterTouch.rows[0];
  assert(afterSession, "session must resolve after touch test");
  check("(12) authenticated request rolls idle expiry forward", new Date(afterSession.idle_expires_at).getTime() > new Date(beforeSession.idle_expires_at).getTime(), { beforeSession, afterSession });
  check("(13) rolled idle expiry never exceeds absolute expiry", new Date(afterSession.idle_expires_at).getTime() <= new Date(afterSession.absolute_expires_at).getTime(), afterSession);

  const missingCsrf = await app.inject({
    method: "POST",
    url: "/v1/auth/workspace",
    headers: { cookie: cookies, origin: APP_ORIGIN },
    payload: { workspaceId: primaryWorkspace }
  });
  check("(14) unsafe session route rejects missing CSRF token", missingCsrf.statusCode === 403, missingCsrf.body);

  const wrongCsrf = await app.inject({
    method: "POST",
    url: "/v1/auth/workspace",
    headers: { cookie: cookies, origin: APP_ORIGIN, "x-csrf-token": "wrong-token" },
    payload: { workspaceId: primaryWorkspace }
  });
  check("(15) unsafe session route rejects wrong CSRF token", wrongCsrf.statusCode === 403, wrongCsrf.body);

  const wrongOrigin = await app.inject({
    method: "POST",
    url: "/v1/auth/workspace",
    headers: { cookie: cookies, origin: "https://evil.example", "x-csrf-token": signInBody.csrf_token },
    payload: { workspaceId: primaryWorkspace }
  });
  check("(16) unsafe session route rejects wrong Origin even with correct CSRF token", wrongOrigin.statusCode === 403, wrongOrigin.body);

  const forgedWorkspaceSelection = await app.inject({
    method: "POST",
    url: "/v1/auth/workspace",
    headers: { cookie: cookies, origin: APP_ORIGIN, "x-csrf-token": signInBody.csrf_token },
    payload: { workspaceId: victimWorkspace }
  });
  check("(17) active session cannot select a workspace without membership", [401, 403].includes(forgedWorkspaceSelection.statusCode), forgedWorkspaceSelection.body);

  const forgedCookie = replaceCookie(cookies, "__Host-growth_workspace", victimWorkspace);
  const forgedProductRequest = await app.inject({
    method: "GET",
    url: "/v1/opportunities",
    headers: { cookie: forgedCookie }
  });
  check("(18) forged workspace cookie cannot authorize product access", [401, 403].includes(forgedProductRequest.statusCode), forgedProductRequest.body);

  const ownWorkspaceSelection = await app.inject({
    method: "POST",
    url: "/v1/auth/workspace",
    headers: { cookie: cookies, origin: APP_ORIGIN, "x-csrf-token": signInBody.csrf_token },
    payload: { workspaceId: primaryWorkspace }
  });
  check("(19) active membership may select its own workspace", ownWorkspaceSelection.statusCode === 200, ownWorkspaceSelection.body);

  const malformedCookie = await app.inject({
    method: "GET",
    url: "/v1/auth/session",
    headers: { cookie: "__Host-growth_session=malformed" }
  });
  check("(20) malformed session token is rejected", malformedCookie.statusCode === 401, malformedCookie.body);

  const unknownCookie = await app.inject({
    method: "GET",
    url: "/v1/auth/session",
    headers: { cookie: `__Host-growth_session=${randomBytes(32).toString("base64url")}` }
  });
  check("(21) unknown session token is rejected", unknownCookie.statusCode === 401, unknownCookie.body);

  const noWorkspaceSignin = await app.inject({
    method: "POST",
    url: "/v1/auth/signin",
    headers: { origin: APP_ORIGIN },
    payload: { email: noWorkspace.email, password: noWorkspace.password }
  });
  const noWorkspaceBody = noWorkspaceSignin.json();
  check("(22) authenticated user with no workspace can sign in", noWorkspaceSignin.statusCode === 200 && noWorkspaceBody.workspaces?.length === 0, noWorkspaceSignin.body);
  const noWorkspaceCookies = cookieHeaderFromSetCookies(setCookies(noWorkspaceSignin));
  const noWorkspaceProduct = await app.inject({
    method: "GET",
    url: "/v1/opportunities",
    headers: { cookie: noWorkspaceCookies }
  });
  check("(23) authenticated user without selected active workspace is rejected", noWorkspaceProduct.statusCode === 409, noWorkspaceProduct.body);

  // A short-lived session proves expiration independently of revocation.
  const expiringRaw = randomBytes(32).toString("base64url");
  await withUserTransaction(primary.userId, async (client) => {
    await client.query(
      `select growth.identity_create_session(
        $1,$2,array['password']::text[],now() + interval '3 seconds',now() + interval '1 second',null,null
      )`,
      [primary.userId, sha256(expiringRaw)]
    );
  });
  await new Promise((resolve) => setTimeout(resolve, 1200));
  const expiredRes = await app.inject({
    method: "GET",
    url: "/v1/auth/session",
    headers: { cookie: `__Host-growth_session=${expiringRaw}` }
  });
  check("(24) idle-expired session is rejected", expiredRes.statusCode === 401, expiredRes.body);

  const signOutRes = await app.inject({
    method: "POST",
    url: "/v1/auth/signout",
    headers: { cookie: cookies, origin: APP_ORIGIN, "x-csrf-token": signInBody.csrf_token }
  });
  check("(25) signout revokes current session", signOutRes.statusCode === 204, signOutRes.body);
  const afterLogout = await app.inject({ method: "GET", url: "/v1/context", headers: { cookie: cookies } });
  check("(26) revoked session is rejected on next request", afterLogout.statusCode === 401, afterLogout.body);

  // Two fresh sessions, then logout-all from one must revoke both.
  const signInA = await app.inject({ method: "POST", url: "/v1/auth/signin", headers: { origin: APP_ORIGIN }, payload: { email: primary.email, password: primary.password } });
  const signInB = await app.inject({ method: "POST", url: "/v1/auth/signin", headers: { origin: APP_ORIGIN }, payload: { email: primary.email, password: primary.password } });
  check("(27) two concurrent account sessions can be created", signInA.statusCode === 200 && signInB.statusCode === 200, { a: signInA.body, b: signInB.body });
  const bodyA = signInA.json();
  const cookiesA = cookieHeaderFromSetCookies(setCookies(signInA));
  const cookiesB = cookieHeaderFromSetCookies(setCookies(signInB));

  const logoutAll = await app.inject({
    method: "POST",
    url: "/v1/auth/signout-all",
    headers: { cookie: cookiesA, origin: APP_ORIGIN, "x-csrf-token": bodyA.csrf_token }
  });
  check("(28) logout-all succeeds", logoutAll.statusCode === 200 && logoutAll.json()?.revoked_sessions >= 2, logoutAll.body);
  const afterAllA = await app.inject({ method: "GET", url: "/v1/auth/session", headers: { cookie: cookiesA } });
  const afterAllB = await app.inject({ method: "GET", url: "/v1/auth/session", headers: { cookie: cookiesB } });
  check("(29) logout-all revokes initiating session", afterAllA.statusCode === 401, afterAllA.body);
  check("(30) logout-all revokes other active session", afterAllB.statusCode === 401, afterAllB.body);

  // New successful login establishes the reset point; then configured consecutive failures block the email.
  const throttleReset = await app.inject({ method: "POST", url: "/v1/auth/signin", headers: { origin: APP_ORIGIN }, payload: { email: primary.email, password: primary.password } });
  check("(31) successful signin before throttle sequence succeeds", throttleReset.statusCode === 200, throttleReset.body);

  const maxEmailFailures = Number(process.env.LOGIN_MAX_EMAIL_FAILURES ?? 5);
  for (let index = 0; index < maxEmailFailures; index++) {
    const failure = await app.inject({
      method: "POST",
      url: "/v1/auth/signin",
      headers: { origin: APP_ORIGIN, "x-real-ip": "203.0.113.42" },
      payload: { email: primary.email, password: `wrong-${index}` }
    });
    check(`(32.${index + 1}) wrong password attempt is generic unauthorized before threshold`, failure.statusCode === 401, failure.body);
  }
  const blocked = await app.inject({
    method: "POST",
    url: "/v1/auth/signin",
    headers: { origin: APP_ORIGIN, "x-real-ip": "203.0.113.42" },
    payload: { email: primary.email, password: primary.password }
  });
  check("(33) email throttle blocks after configured consecutive failures", blocked.statusCode === 429, blocked.body);

  // Transaction-local tenant context must not survive commit on a reused pool connection.
  const poolClient = await db.connect();
  try {
    await poolClient.query("BEGIN");
    await poolClient.query("select set_config('app.user_id',$1,true)", [primary.userId]);
    await poolClient.query("select set_config('app.workspace_id',$1,true)", [primaryWorkspace]);
    await poolClient.query("COMMIT");
    const state = await poolClient.query<{ user_id: string | null; workspace_id: string | null }>(
      `select nullif(current_setting('app.user_id',true),'') as user_id,
              nullif(current_setting('app.workspace_id',true),'') as workspace_id`
    );
    check("(34) committed transaction does not leak app.user_id/app.workspace_id into pool reuse",
      state.rows[0]?.user_id === null && state.rows[0]?.workspace_id === null,
      state.rows[0]
    );
  } finally {
    poolClient.release();
  }
} finally {
  await app.close();
  await db.end();
}

process.exit(failures > 0 ? 1 : 0);
