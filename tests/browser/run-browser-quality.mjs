#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "../..");

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: ROOT,
    stdio: "inherit",
    env: process.env
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

if (process.env.CI !== "true") {
  console.log("BROWSER QUALITY GATE: skipped outside CI; run the Playwright command explicitly for local browser validation.");
  process.exit(0);
}

console.log("BROWSER QUALITY GATE: installing exact CI-only browser tooling without modifying package manifests or lockfile.");
run("npm", [
  "install",
  "--no-save",
  "--package-lock=false",
  "--no-audit",
  "--no-fund",
  "@playwright/test@1.63.0",
  "@axe-core/playwright@4.13.0"
]);

const playwright = join(ROOT, "node_modules", ".bin", "playwright");
run(playwright, ["install", "--with-deps", "chromium", "firefox", "webkit"]);
run(playwright, ["test", "--config=tests/browser/playwright.config.ts"]);
console.log("BROWSER QUALITY GATE: PASSED — Chromium, Firefox and WebKit browser journeys completed.");
