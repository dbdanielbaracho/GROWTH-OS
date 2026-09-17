import { randomUUID } from "node:crypto";
import assert from "node:assert/strict";
import { buildApp } from "../src/app.js";
import { db } from "../src/db.js";

if (process.env.NODE_ENV !== "production") {
  throw new Error("identity-lifecycle.integration.mts must run with NODE_ENV=production");
}

const APP_ORIGIN = process.env.APP_ORIGIN;
const EMAIL_API_URL = process.env.IDENTITY_EMAIL_API_URL;
if (!APP_ORIGIN || !EMAIL_API_URL) throw new Error("APP_ORIGIN and IDENTITY_EMAIL_API_URL are required");

type CapturedEmail = { from: string; to: string[]; subject: string; html: string };
const capturedEmails: CapturedEmail[] = [];
const originalFetch = globalThis.fetch;
globalThis.fetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
  const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
  if (url === EMAIL_API_URL) {
    capturedEmails.push(JSON.parse(String(init?.body ?? "{}")) as CapturedEmail);
    return new Response(JSON.stringify({ id: randomUUID() }), {
      status: 200,
      headers: { "content-type": "application/json" }
    });
  }
  return originalFetch(input, init);
};

class CookieJar {
  private readonly values = new Map<string, string>();

  absorb(response: { headers: Record<string, unknown> }): void {
    const raw = response.headers["set-cookie"];
    const rows = Array.isArray(raw) ? raw.map(String) : raw ? [String(raw)] : [];
    for (const row of rows) {
      const first = row.split(";", 1)[0] ?? "";
      const separator = first.indexOf("=");
      if (separator <= 0) continue;
      const name = first.slice(0, separator);
      const value = first.slice(separator + 1);
      if (value) this.values.set(name, value);
      else this.values.delete(name);
    }
  }

  header(): string {
    return [...this.values.entries()].map(([name, value]) => `${name}=${value}`).join("; ");
  }
}

function verificationToken(email: CapturedEmail): string {
  const match = email.html.match(/[?&]token=([^"&<]+)/);
  if (!match?.[1]) throw new Error("verification token not found in captured email");
  return decodeURIComponent(match[1]);
}

function invitationToken(email: CapturedEmail): string {
  const match = email.html.match(/<code>([^<]+)<\/code>/);
  if (!match?.[1]) throw new Error("invitation token not found in captured email");
  return match[1];
}

function latestEmail(subject: string, recipient: string): CapturedEmail {
  const email = [...capturedEmails].reverse().find((item) =>
    item.subject === subject && item.to.includes(recipient)
  );
  if (!email) throw new Error(`captured email not found: ${subject} -> ${recipient}`);
  return email;
}

async function signupVerifyAndSignin(app: ReturnType<typeof buildApp>, email: string, password: string) {
  const signup = await app.inject({
    method: "POST",
    url: "/v1/auth/signup",
    headers: { origin: APP_ORIGIN },
    payload: { email, password }
  });
  assert.equal(signup.statusCode, 202, signup.body);
  assert.equal(signup.json()?.status, "verification_required");

  const verify = await app.inject({
    method: "POST",
    url: "/v1/auth/verify-email",
    headers: { origin: APP_ORIGIN },
    payload: { token: verificationToken(latestEmail("Verify your Growth OS email", email)) }
  });
  assert.equal(verify.statusCode, 200, verify.body);
  assert.equal(verify.json()?.status, "verified");

  const signin = await app.inject({
    method: "POST",
    url: "/v1/auth/signin",
    headers: { origin: APP_ORIGIN },
    payload: { email, password }
  });
  assert.equal(signin.statusCode, 200, signin.body);
  const body = signin.json();
  assert.equal(typeof body.csrf_token, "string");
  const cookies = new CookieJar();
  cookies.absorb(signin);
  return { body, cookies, csrf: String(body.csrf_token), userId: String(body.session.user_id) };
}

const tag = randomUUID().slice(0, 8);
const ownerEmail = `identity-owner-${tag}@example.com`;
const memberEmail = `identity-member-${tag}@example.com`;
const ownerPassword = `Owner!${tag}Aa9-secure`;
const memberPassword = `Member!${tag}Bb9-secure`;
const app = buildApp(false);

try {
  const owner = await signupVerifyAndSignin(app, ownerEmail, ownerPassword);
  assert.equal(owner.body.workspaces.length, 0);

  const createWorkspace = await app.inject({
    method: "POST",
    url: "/v1/workspaces",
    headers: {
      origin: APP_ORIGIN,
      cookie: owner.cookies.header(),
      "x-csrf-token": owner.csrf
    },
    payload: {
      name: `Identity lifecycle ${tag}`,
      defaultMarket: "BR",
      defaultLanguage: "pt-BR",
      defaultTimezone: "America/Sao_Paulo"
    }
  });
  assert.equal(createWorkspace.statusCode, 200, createWorkspace.body);
  const workspaceId = String(createWorkspace.json()?.workspace_id);
  assert.match(workspaceId, /^[0-9a-f-]{36}$/i);
  owner.cookies.absorb(createWorkspace);

  const ownerContext = await app.inject({
    method: "GET",
    url: "/v1/context",
    headers: { cookie: owner.cookies.header() }
  });
  assert.equal(ownerContext.statusCode, 200, ownerContext.body);
  assert.equal(ownerContext.json()?.context?.workspace_id, workspaceId);

  const member = await signupVerifyAndSignin(app, memberEmail, memberPassword);
  assert.equal(member.body.workspaces.length, 0);

  const invite = await app.inject({
    method: "POST",
    url: `/v1/workspaces/${workspaceId}/invitations`,
    headers: {
      origin: APP_ORIGIN,
      cookie: owner.cookies.header(),
      "x-csrf-token": owner.csrf
    },
    payload: { email: memberEmail, role: "viewer", canPublish: false }
  });
  assert.equal(invite.statusCode, 202, invite.body);
  assert.equal(invite.json()?.status, "invitation_sent");

  const token = invitationToken(latestEmail("You were invited to Growth OS", memberEmail));
  const accept = await app.inject({
    method: "POST",
    url: "/v1/auth/invitations/accept",
    headers: {
      origin: APP_ORIGIN,
      cookie: member.cookies.header(),
      "x-csrf-token": member.csrf
    },
    payload: { token }
  });
  assert.equal(accept.statusCode, 200, accept.body);
  assert.equal(accept.json()?.workspace_id, workspaceId);
  member.cookies.absorb(accept);

  const replay = await app.inject({
    method: "POST",
    url: "/v1/auth/invitations/accept",
    headers: {
      origin: APP_ORIGIN,
      cookie: member.cookies.header(),
      "x-csrf-token": member.csrf
    },
    payload: { token }
  });
  assert.equal(replay.statusCode, 409, replay.body);

  const memberContext = await app.inject({
    method: "GET",
    url: "/v1/context",
    headers: { cookie: member.cookies.header() }
  });
  assert.equal(memberContext.statusCode, 200, memberContext.body);
  assert.equal(memberContext.json()?.context?.workspace_id, workspaceId);

  const forbiddenMembers = await app.inject({
    method: "GET",
    url: `/v1/workspaces/${workspaceId}/members`,
    headers: { cookie: member.cookies.header() }
  });
  assert.equal(forbiddenMembers.statusCode, 403, forbiddenMembers.body);

  const membersBefore = await app.inject({
    method: "GET",
    url: `/v1/workspaces/${workspaceId}/members`,
    headers: { cookie: owner.cookies.header() }
  });
  assert.equal(membersBefore.statusCode, 200, membersBefore.body);
  assert.equal(membersBefore.json()?.members?.length, 2);

  const updateMember = await app.inject({
    method: "PATCH",
    url: `/v1/workspaces/${workspaceId}/members/${member.userId}`,
    headers: {
      origin: APP_ORIGIN,
      cookie: owner.cookies.header(),
      "x-csrf-token": owner.csrf
    },
    payload: { role: "editor", canPublish: true, status: "active" }
  });
  assert.equal(updateMember.statusCode, 200, updateMember.body);
  assert.equal(updateMember.json()?.member?.role, "editor");
  assert.equal(updateMember.json()?.member?.can_publish, true);

  const forgedWorkspace = randomUUID();
  const forbiddenSelection = await app.inject({
    method: "POST",
    url: "/v1/auth/workspace",
    headers: {
      origin: APP_ORIGIN,
      cookie: member.cookies.header(),
      "x-csrf-token": member.csrf
    },
    payload: { workspaceId: forgedWorkspace }
  });
  assert.ok([401, 403].includes(forbiddenSelection.statusCode), forbiddenSelection.body);

  const crossTenantRows = await db.query<{ count: string }>(
    `select count(*)::text as count
       from growth.memberships
      where workspace_id=$1 and user_id=$2`,
    [forgedWorkspace, member.userId]
  );
  assert.equal(crossTenantRows.rows[0]?.count, "0");

  console.log("PASS identity lifecycle: signup -> verify -> signin -> workspace -> invite -> accept -> role update -> isolation");
} finally {
  globalThis.fetch = originalFetch;
  await app.close();
  await db.end();
}
