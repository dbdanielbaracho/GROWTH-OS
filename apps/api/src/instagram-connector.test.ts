import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";

process.env.DATABASE_URL ??= "postgresql://ci:ci@127.0.0.1:5432/ci";
process.env.CSRF_SECRET ??= "ci-instagram-state-secret-with-more-than-32-characters";
process.env.APP_ORIGIN ??= "https://ci.growth-os.invalid";
process.env.INSTAGRAM_APP_ID ??= "ci-instagram-app-id";
process.env.INSTAGRAM_APP_SECRET ??= "ci-instagram-app-secret";
process.env.PROVIDER_CREDENTIALS_KEY_B64URL ??= randomBytes(32).toString("base64url");

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
