import assert from "node:assert/strict";
import test from "node:test";
import { CreateContentSchema } from "./content.js";

test("CreateContentSchema accepts a valid draft", () => {
  const result = CreateContentSchema.parse({
    market: "US",
    language: "en",
    sourceType: "manual",
    body: "A useful post",
    structure: { hook: "clear" }
  });

  assert.equal(result.market, "US");
  assert.equal(result.language, "en");
  assert.equal(result.body, "A useful post");
});

test("CreateContentSchema rejects missing market", () => {
  assert.throws(() =>
    CreateContentSchema.parse({
      language: "en",
      sourceType: "manual"
    })
  );
});

test("CreateContentSchema rejects oversized body", () => {
  assert.throws(() =>
    CreateContentSchema.parse({
      market: "US",
      language: "en",
      sourceType: "manual",
      body: "x".repeat(100_001)
    })
  );
});
