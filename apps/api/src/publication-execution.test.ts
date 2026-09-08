import assert from "node:assert/strict";
import test from "node:test";
import {
  classifyProviderResponse,
  preparePublicationProviderResult,
  providerPayloadRef,
  publicationRequestHash,
  toFinalizationArguments
} from "./publication-execution.js";

test("publication request hash is stable when object keys are reordered", () => {
  const base = {
    provider: "instagram" as const,
    socialAccountId: "11111111-1111-4111-8111-111111111111",
    contentVersionId: "22222222-2222-4222-8222-222222222222",
    attemptNo: 1,
    body: "launch",
    structure: { caption: { language: "pt-BR", format: "plain" }, asset: "https://cdn.example/a.jpg" },
    assetRefs: ["https://cdn.example/a.jpg"]
  };
  const reordered = {
    ...base,
    structure: { asset: "https://cdn.example/a.jpg", caption: { format: "plain", language: "pt-BR" } }
  };
  assert.equal(publicationRequestHash(base), publicationRequestHash(reordered));
});

test("publication request hash changes on factual payload changes", () => {
  const base = {
    provider: "youtube" as const,
    socialAccountId: "11111111-1111-4111-8111-111111111111",
    contentVersionId: "22222222-2222-4222-8222-222222222222",
    attemptNo: 1,
    body: "launch",
    structure: { title: "A" },
    assetRefs: []
  };
  assert.notEqual(
    publicationRequestHash(base),
    publicationRequestHash({ ...base, body: "different" })
  );
});

test("provider responses are fail-closed", () => {
  assert.equal(classifyProviderResponse(201, "provider-123"), "confirmed");
  assert.equal(classifyProviderResponse(201, null), "failed_retryable");
  assert.equal(classifyProviderResponse(429, null), "failed_retryable");
  assert.equal(classifyProviderResponse(503, null), "failed_retryable");
  assert.equal(classifyProviderResponse(401, null), "needs_user_action");
  assert.equal(classifyProviderResponse(409, null), "needs_user_action");
});

test("finalization arguments contain only a payload digest, never raw provider data", () => {
  const result = preparePublicationProviderResult({
    httpStatus: 201,
    providerRequestId: "request-1",
    providerContentId: "content-1",
    providerPermalink: "https://example.com/content-1",
    startedAt: "2026-09-08T00:00:00.000Z",
    providerRespondedAt: "2026-09-08T00:00:01.000Z",
    rawPayload: { access_token: "must-not-be-persisted", id: "content-1" }
  });
  const finalization = toFinalizationArguments(result, "request-hash");
  assert.match(finalization.rawPayloadRef ?? "", /^sha256:[a-f0-9]{64}$/);
  assert.equal(JSON.stringify(finalization).includes("must-not-be-persisted"), false);
  assert.equal(finalization.requestHash, "request-hash");
  assert.equal(providerPayloadRef({ b: 2, a: 1 }), providerPayloadRef({ a: 1, b: 2 }));
});

test("confirmed result rejects an unusable provider permalink", () => {
  assert.throws(() =>
    preparePublicationProviderResult({
      httpStatus: 201,
      providerContentId: "content-1",
      providerPermalink: "not-a-url"
    })
  );
});
