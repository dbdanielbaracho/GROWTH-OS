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

const requestedProjects = (process.env.BROWSER_QUALITY_PROJECTS ?? "chromium,firefox,webkit")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);
const supportedProjects = new Set(["chromium", "firefox", "webkit"]);
if (requestedProjects.length === 0 || requestedProjects.some((project) => !supportedProjects.has(project))) {
  throw new Error("BROWSER_QUALITY_PROJECTS must contain chromium, firefox, or webkit");
}

console.log(`BROWSER QUALITY GATE: installing exact CI-only tooling for ${requestedProjects.join(", ")} without modifying package manifests or lockfile.`);
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
run(playwright, ["install", "--with-deps", ...requestedProjects]);
run(playwright, [
  "test",
  "--config=tests/browser/playwright.config.ts",
  ...requestedProjects.map((project) => `--project=${project}`)
]);
console.log(`BROWSER QUALITY GATE: PASSED — ${requestedProjects.join(", ")} browser journeys completed.`);
