import assert from "node:assert/strict";
import test from "node:test";
import {
  executePublicationIntent,
  PublicationProviderError,
  type ClaimablePublicationIntent
} from "./publication-worker.js";

const claimed: ClaimablePublicationIntent = {
  workspaceId: "11111111-1111-4111-8111-111111111111",
  publicationIntentId: "22222222-2222-4222-8222-222222222222",
  claimToken: "33333333-3333-4333-8333-333333333333",
  attemptNo: 1,
  provider: "instagram",
  socialAccountId: "44444444-4444-4444-8444-444444444444",
  contentVersionId: "55555555-5555-4555-8555-555555555555",
  body: "caption",
  structure: { media_type: "IMAGE", asset: "https://cdn.example/a.jpg" },
  assetRefs: ["https://cdn.example/a.jpg"]
};

function storeForClaim() {
  const finalized: Array<{ claimed: ClaimablePublicationIntent; result: Record<string, unknown> }> = [];
  return {
    finalized,
    store: {
      claim: async () => claimed,
      finalize: async (current: ClaimablePublicationIntent, result: Record<string, unknown>) => {
        finalized.push({ claimed: current, result });
        return { status: result.outcome };
      }
    }
  };
}

test("worker claims once, calls the adapter, and finalizes once", async () => {
  const { store, finalized } = storeForClaim();
  let calls = 0;
  const response = await executePublicationIntent({
    store,
    adapter: {
      publish: async ({ requestHash }) => {
        calls += 1;
        assert.match(requestHash, /^[a-f0-9]{64}$/);
        return {
          outcome: "confirmed",
          httpStatus: 201,
          providerRequestId: "provider-request",
          providerContentId: "provider-content",
          providerPermalink: "https://provider.example/content",
          startedAt: null,
          providerRespondedAt: null,
          rawPayload: { id: "provider-content" }
        };
      }
    }
  });
  assert.deepEqual(response, { status: "confirmed" });
  assert.equal(calls, 1);
  assert.equal(finalized.length, 1);
  const final = finalized[0];
  assert.ok(final);
  assert.equal(final.claimed.attemptNo, 1);
});

test("transient provider failures finalize as retryable without leaking the error message", async () => {
  const { store, finalized } = storeForClaim();
  await executePublicationIntent({
    store,
    adapter: {
      publish: async () => {
        throw new PublicationProviderError(429, "provider-request-429", "token must not be persisted");
      }
    }
  });
  const final = finalized[0];
  assert.ok(final);
  assert.equal(final.result.outcome, "failed_retryable");
  assert.equal(final.result.httpStatus, 429);
  assert.equal(final.result.providerRequestId, "provider-request-429");
  assert.match(String(final.result.rawPayloadRef), /^sha256:[a-f0-9]{64}$/);
  assert.equal(JSON.stringify(final.result).includes("token must not be persisted"), false);
});

test("provider authorization failures finalize as user action", async () => {
  const { store, finalized } = storeForClaim();
  await executePublicationIntent({
    store,
    adapter: {
      publish: async () => {
        throw new PublicationProviderError(403);
      }
    }
  });
  const final = finalized[0];
  assert.ok(final);
  assert.equal(final.result.outcome, "needs_user_action");
});


test("worker constructs the provider adapter only after the claim", async () => {
  const { store, finalized } = storeForClaim();
  let factoryClaim: ClaimablePublicationIntent | null = null;
  const response = await executePublicationIntent({
    store,
    adapterFactory: (claimedIntent) => {
      factoryClaim = claimedIntent;
      return {
        publish: async () => ({
          outcome: "confirmed",
          httpStatus: 200,
          providerRequestId: "factory-request",
          providerContentId: "factory-content",
          providerPermalink: "https://provider.example/factory-content",
          startedAt: null,
          providerRespondedAt: null,
          rawPayload: { id: "factory-content" }
        })
      };
    }
  });
  assert.deepEqual(response, { status: "confirmed" });
  assert.equal(factoryClaim?.publicationIntentId, claimed.publicationIntentId);
  assert.equal(finalized.length, 1);
});
