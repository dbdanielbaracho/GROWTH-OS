import { createCipheriv, randomBytes } from "node:crypto";
import assert from "node:assert/strict";
import test from "node:test";

process.env.DATABASE_URL ??= "postgres://test:test@127.0.0.1:5432/test";
const { createPublicationProviderAdapter } =
  await import("./publication-adapter-composition.js");

function sealCredential(
  accessToken: string,
  provider: "instagram" | "youtube",
  workspaceId: string,
  connectionId: string
): Buffer {
  const key = Buffer.alloc(32, 7);
  process.env.PROVIDER_CREDENTIALS_KEY_B64URL = key.toString("base64url");
  const nonce = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(Buffer.from(`${provider}-credential:v1:${workspaceId}:${connectionId}`, "utf8"));
  const encrypted = Buffer.concat([
    cipher.update(JSON.stringify({ accessToken }), "utf8"),
    cipher.final()
  ]);
  return Buffer.from([
    nonce.toString("base64url"),
    cipher.getAuthTag().toString("base64url"),
    encrypted.toString("base64url")
  ].join("."), "utf8");
}

test("composition decrypts the protected credential and invokes Instagram adapter", async () => {
  process.env.PUBLICATION_ASSET_HOSTS = "cdn.example.com";
  const workspaceId = "b0000000-0000-4000-8000-000000000001";
  const connectionId = "c0000000-0000-4000-8000-000000000981";
  const claimed = {
    workspaceId,
    publicationIntentId: "c0000000-0000-4000-8000-000000000982",
    claimToken: "c0000000-0000-4000-8000-000000000983",
    attemptNo: 1,
    provider: "instagram" as const,
    socialAccountId: "c0000000-0000-4000-8000-000000000984",
    contentVersionId: "c0000000-0000-4000-8000-000000000985",
    body: "caption",
    structure: { mediaKind: "image" },
    assetRefs: ["asset", "https://cdn.example.com/post.jpg"],
    connectionId,
    storageRef: "https://cdn.example.com/post.jpg",
    mimeType: "image/jpeg",
    bytes: 10,
    providerAccountId: "17890000000000000",
    credentialCiphertext: sealCredential("secret-token", "instagram", workspaceId, connectionId)
  };
  const calls: string[] = [];
  const adapter = createPublicationProviderAdapter(claimed, {
    fetchImpl: async (input) => {
      calls.push(String(input));
      return calls.length === 1
        ? new Response(JSON.stringify({ id: "container-1" }), { status: 200 })
        : new Response(JSON.stringify({ id: "published-1" }), { status: 200 });
    }
  });

  const result = await adapter.publish({ claimed, requestHash: "hash" });
  assert.equal(result.outcome, "confirmed");
  assert.equal(result.providerContentId, "published-1");
  assert.deepEqual(calls, [
    "https://graph.instagram.com/v24.0/17890000000000000/media",
    "https://graph.instagram.com/v24.0/17890000000000000/media_publish"
  ]);
});

test("composition fails closed when asset host allowlist is empty", async () => {
  process.env.PUBLICATION_ASSET_HOSTS = "";
  const adapter = createPublicationProviderAdapter({
    workspaceId: "b0000000-0000-4000-8000-000000000001",
    publicationIntentId: "c0000000-0000-4000-8000-000000000992",
    claimToken: "c0000000-0000-4000-8000-000000000993",
    attemptNo: 1,
    provider: "instagram" as const,
    socialAccountId: "c0000000-0000-4000-8000-000000000994",
    contentVersionId: "c0000000-0000-4000-8000-000000000995",
    body: null,
    structure: {},
    assetRefs: ["asset"],
    connectionId: "c0000000-0000-4000-8000-000000000996",
    storageRef: "https://cdn.example.com/post.jpg",
    providerAccountId: "17890000000000000",
    credentialCiphertext: Buffer.from("invalid")
  });
  await assert.rejects(
    adapter.publish({ claimed: {} as never, requestHash: "hash" }),
    (error: unknown) =>
      error instanceof Error
      && error.name === "PublicationProviderError"
      && (error as { httpStatus?: number }).httpStatus === 422
  );
});
