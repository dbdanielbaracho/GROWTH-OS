import assert from "node:assert/strict";
import test from "node:test";
import { CreateContentSchema, contentChecksum } from "./content.js";

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

test("CreateContentSchema rejects oversized structure JSON", () => {
  assert.throws(() =>
    CreateContentSchema.parse({
      market: "US",
      language: "en",
      sourceType: "manual",
      structure: { payload: "x".repeat(100_001) }
    })
  );
});

test("contentChecksum is stable across object key order", () => {
  const first = contentChecksum("same", { a: 1, nested: { x: 1, y: 2 }, b: 2 });
  const second = contentChecksum("same", { b: 2, nested: { y: 2, x: 1 }, a: 1 });
  assert.equal(first, second);
});
