import assert from "node:assert/strict";
import test from "node:test";
import { operationalRoute, operationalSeverity, operationalSloClass } from "./operational-telemetry.js";

test("operational telemetry uses route templates instead of user-controlled URLs", () => {
  assert.equal(operationalRoute({ routeOptions: { url: "/v1/content/:id" } } as never), "/v1/content/:id");
  assert.equal(operationalRoute({ routeOptions: { url: undefined } } as never), "unmatched");
});

test("operational telemetry maps bounded SLO classes", () => {
  assert.equal(operationalSloClass("/health/ready"), "health");
  assert.equal(operationalSloClass("/v1/auth/signin"), "identity");
  assert.equal(operationalSloClass("/v1/integrations/youtube/sync"), "provider");
  assert.equal(operationalSloClass("/v1/opportunities"), "tenant_api");
  assert.equal(operationalSloClass("unmatched"), "unmatched");
});

test("operational telemetry severity follows HTTP outcome without logging payloads", () => {
  assert.equal(operationalSeverity(200), "info");
  assert.equal(operationalSeverity(401), "warn");
  assert.equal(operationalSeverity(503), "error");
});
