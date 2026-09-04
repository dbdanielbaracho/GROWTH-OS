import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";

process.env.DATABASE_URL ??= "postgresql://ci:ci@127.0.0.1:5432/ci";
process.env.CSRF_SECRET ??= "ci-youtube-state-secret-with-more-than-32-characters";
process.env.APP_ORIGIN ??= "https://ci.growth-os.invalid";
process.env.YOUTUBE_OAUTH_CLIENT_ID ??= "ci-client-id";
process.env.YOUTUBE_OAUTH_CLIENT_SECRET ??= "ci-client-secret";
process.env.PROVIDER_CREDENTIALS_KEY_B64URL ??= randomBytes(32).toString("base64url");

const connector = await import("./youtube-connector.js");

test("YouTube OAuth state round-trips and does not expose tenant identifiers", () => {
  const state = {
    v: 1 as const,
    userId: "11111111-1111-4111-8111-111111111111",
    workspaceId: "22222222-2222-4222-8222-222222222222",
    managedAccountId: "33333333-3333-4333-8333-333333333333",
    connectionId: "44444444-4444-4444-8444-444444444444",
    nonce: "test-nonce",
    expiresAt: Date.now() + 60_000
  };

  const sealed = connector.sealYoutubeStateForTest(state);
  assert.equal(sealed.includes(state.userId), false);
  assert.equal(sealed.includes(state.workspaceId), false);
  assert.deepEqual(connector.openYoutubeStateForTest(sealed), state);
});

test("YouTube OAuth state rejects ciphertext tampering", () => {
  const sealed = connector.sealYoutubeStateForTest({
    v: 1,
    userId: "11111111-1111-4111-8111-111111111111",
    workspaceId: "22222222-2222-4222-8222-222222222222",
    managedAccountId: "33333333-3333-4333-8333-333333333333",
    connectionId: "44444444-4444-4444-8444-444444444444",
    nonce: "test-nonce",
    expiresAt: Date.now() + 60_000
  });
  const last = sealed.at(-1);
  assert.ok(last);
  const tampered = `${sealed.slice(0, -1)}${last === "A" ? "B" : "A"}`;
  assert.throws(
    () => connector.openYoutubeStateForTest(tampered),
    (error: unknown) => error instanceof connector.YoutubeConnectorError && error.code === "youtube_state_invalid"
  );
});

test("YouTube views and engagedViews have explicit distinct semantic versions", () => {
  const views = connector.youtubeMetricSemanticVersionForTest("views");
  const engaged = connector.youtubeMetricSemanticVersionForTest("engagedViews");
  assert.match(views.version, /views/);
  assert.match(engaged.version, /engagedViews/);
  assert.notEqual(views.version, engaged.version);
  assert.equal(views.effectiveFrom, "2026-08-24T00:00:00Z");
  assert.equal(engaged.effectiveFrom, "2026-08-24T00:00:00Z");
});
