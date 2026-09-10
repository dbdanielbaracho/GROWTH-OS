import test from "node:test";
import assert from "node:assert/strict";
import type { FastifyRequest } from "fastify";

process.env.DATABASE_URL ??= "postgresql://ci:ci@127.0.0.1:5432/ci";
process.env.NODE_ENV = "production";
process.env.APP_ORIGIN = "https://growth-os-production-d120.up.railway.app";
process.env.APP_TRUSTED_ORIGINS = "https://growos.predibeacon.com";
process.env.CSRF_SECRET = "ci-origin-secret-with-more-than-32-characters";

const { assertTrustedOrigin, IdentityCsrfError } = await import("./identity-adapter.js");

function requestWithOrigin(origin: string): FastifyRequest {
  return { headers: { origin } } as unknown as FastifyRequest;
}

test("CSRF Origin validation accepts the canonical and custom application origins", () => {
  assert.doesNotThrow(() => assertTrustedOrigin(requestWithOrigin("https://growth-os-production-d120.up.railway.app")));
  assert.doesNotThrow(() => assertTrustedOrigin(requestWithOrigin("https://growos.predibeacon.com")));
});

test("CSRF Origin validation rejects an unrelated origin", () => {
  assert.throws(
    () => assertTrustedOrigin(requestWithOrigin("https://evil.example")),
    (error: unknown) => error instanceof IdentityCsrfError && error.message === "untrusted_origin"
  );
});
