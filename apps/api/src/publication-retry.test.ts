import assert from "node:assert/strict";
import test from "node:test";
import {
  MAX_PUBLICATION_RETRIES,
  nextPublicationRetryAt,
  publicationRetryDelayMs
} from "./publication-retry.js";

test("publication retry policy is bounded exponential backoff", () => {
  assert.equal(publicationRetryDelayMs(0), 60_000);
  assert.equal(publicationRetryDelayMs(1), 120_000);
  assert.equal(publicationRetryDelayMs(4), 960_000);
  assert.equal(publicationRetryDelayMs(MAX_PUBLICATION_RETRIES), 1_800_000);
  assert.equal(publicationRetryDelayMs(99), 1_800_000);
});

test("publication retry policy returns a future retry time", () => {
  const now = new Date("2026-09-08T18:00:00.000Z");
  assert.equal(
    nextPublicationRetryAt(now, 2).toISOString(),
    "2026-09-08T18:04:00.000Z"
  );
});
