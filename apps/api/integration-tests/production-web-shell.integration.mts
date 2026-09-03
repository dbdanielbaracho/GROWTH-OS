import assert from "node:assert/strict";
import { buildApp } from "../src/app.js";
import { registerProductionWeb } from "../src/production-web.js";

if (process.env.NODE_ENV !== "production") {
  throw new Error("production-web-shell.integration.mts must run with NODE_ENV=production");
}

const app = buildApp(false);

try {
  await registerProductionWeb(app);

  const root = await app.inject({ method: "GET", url: "/" });
  assert.equal(root.statusCode, 200, root.body);
  assert.match(String(root.headers["content-type"] ?? ""), /text\/html/i);
  assert.match(root.body, /Growth OS/i);
  assert.match(String(root.headers["content-security-policy"] ?? ""), /default-src 'self'/);
  assert.match(String(root.headers["content-security-policy"] ?? ""), /connect-src 'self'/);
  assert.equal(root.headers["strict-transport-security"], "max-age=31536000; includeSubDomains");
  assert.equal(root.headers["x-content-type-options"], "nosniff");
  assert.equal(root.headers["x-frame-options"], "DENY");
  assert.equal(root.headers["cache-control"], "no-store");

  // The static wildcard must never shadow the application's API routes.
  const system = await app.inject({ method: "GET", url: "/v1/system" });
  assert.equal(system.statusCode, 200, system.body);
  assert.equal(system.json()?.name, "Growth OS");

  console.log("PASS: production serves reviewed web + API from one origin with document security headers");
} finally {
  await app.close();
}
