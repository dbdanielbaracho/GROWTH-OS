import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";

process.env.DATABASE_URL ??= "postgresql://ci:ci@127.0.0.1:5432/ci";
process.env.CSRF_SECRET ??= "ci-instagram-state-secret-with-more-than-32-characters";
process.env.APP_ORIGIN ??= "https://ci.growth-os.invalid";
process.env.INSTAGRAM_APP_ID ??= "ci-instagram-app-id";
process.env.INSTAGRAM_APP_SECRET ??= "ci-instagram-app-secret";
process.env.PROVIDER_CREDENTIALS_KEY_B64URL ??= randomBytes(32).toString("base64url");
process.env.INSTAGRAM_GRAPH_API_VERSION = "v24.0";

const connector = await import("./instagram-connector.js");

function state() {
  return {
    v: 1 as const,
    userId: "11111111-1111-4111-8111-111111111111",
    workspaceId: "22222222-2222-4222-8222-222222222222",
    managedAccountId: "33333333-3333-4333-8333-333333333333",
    connectionId: "44444444-4444-4444-8444-444444444444",
    nonce: "test-nonce",
    expiresAt: Date.now() + 60_000
  };
}

test("Instagram configuration accepts the default dotted Graph API version", () => {
  assert.equal(connector.instagramConnectorConfigured(), true);
});

test("Instagram configuration rejects malformed Graph API versions", () => {
  const previous = process.env.INSTAGRAM_GRAPH_API_VERSION;
  process.env.INSTAGRAM_GRAPH_API_VERSION = "v24";
  try {
    assert.throws(
      () => connector.instagramConnectorConfigured(),
      (error: unknown) =>
        error instanceof connector.InstagramConnectorError
        && error.code === "instagram_graph_api_version_invalid"
    );
  } finally {
    process.env.INSTAGRAM_GRAPH_API_VERSION = previous;
  }
});

test("Instagram media request is tenant-neutral and bounded to provider fields", () => {
  const url = new URL(connector.instagramMediaRequestUrlForTest("ig id", "v24.0", "cursor value"));
  assert.equal(url.origin, "https://graph.instagram.com");
  assert.equal(url.pathname, "/v24.0/ig%20id/media");
  assert.equal(url.searchParams.get("limit"), "100");
  assert.equal(url.searchParams.get("after"), "cursor value");
  assert.equal(url.searchParams.get("fields")?.includes("like_count"), true);
  assert.equal(url.searchParams.has("access_token"), false);
});

test("Instagram sync schema requires a UUID nonce and bounded lookback", () => {
  assert.equal(connector.InstagramSyncSchema.safeParse({
    connectionId: state().connectionId,
    requestNonce: "55555555-5555-4555-8555-555555555555",
    lookbackDays: 7
  }).success, true);
  assert.equal(connector.InstagramSyncSchema.safeParse({
    connectionId: state().connectionId,
    requestNonce: "not-a-uuid",
    lookbackDays: 7
  }).success, false);
  assert.equal(connector.InstagramSyncSchema.safeParse({
    connectionId: state().connectionId,
    requestNonce: "55555555-5555-4555-8555-555555555555",
    lookbackDays: 31
  }).success, false);
});

test("Instagram refresh endpoint is fixed and carries only the access token", () => {
  const url = new URL(connector.instagramRefreshEndpointForTest("token with spaces"));
  assert.equal(url.origin, "https://graph.instagram.com");
  assert.equal(url.pathname, "/refresh_access_token");
  assert.equal(url.searchParams.get("grant_type"), "ig_refresh_token");
  assert.equal(url.searchParams.get("access_token"), "token with spaces");
  assert.equal(url.searchParams.has("client_secret"), false);
});

test("Instagram OAuth state round-trips without exposing tenant identifiers", () => {
  const input = state();
  const sealed = connector.sealInstagramStateForTest(input);
  assert.equal(sealed.includes(input.userId), false);
  assert.equal(sealed.includes(input.workspaceId), false);
  assert.deepEqual(connector.openInstagramStateForTest(sealed), input);
});

test("Instagram OAuth state rejects ciphertext tampering", () => {
  const sealed = connector.sealInstagramStateForTest(state());
  const last = sealed.at(-1);
  assert.ok(last);
  const tampered = `${sealed.slice(0, -1)}${last === "A" ? "B" : "A"}`;
  assert.throws(
    () => connector.openInstagramStateForTest(tampered),
    (error: unknown) =>
      error instanceof connector.InstagramConnectorError
      && error.code === "instagram_state_invalid"
  );
});
