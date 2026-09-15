import path from "node:path";
import { defineConfig, devices } from "@playwright/test";

const repositoryRoot = process.cwd();
const resultsRoot = path.join(repositoryRoot, "test-results");

export default defineConfig({
  testDir: ".",
  testMatch: "growth-os.browser.spec.ts",
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  workers: 1,
  reporter: process.env.CI
    ? [
        ["line"],
        ["github"],
        ["json", { outputFile: path.join(resultsRoot, "playwright-results.json") }]
      ]
    : "list",
  outputDir: path.join(resultsRoot, "playwright-artifacts"),
  timeout: 30_000,
  expect: { timeout: 8_000 },
  use: {
    baseURL: "http://127.0.0.1:4173",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "off"
  },
  webServer: {
    command: "npm run dev --workspace=@growth-os/web -- --host 127.0.0.1 --port 4173",
    url: "http://127.0.0.1:4173",
    reuseExistingServer: false,
    timeout: 60_000
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } }
    },
    {
      name: "firefox",
      use: { ...devices["Desktop Firefox"], viewport: { width: 1440, height: 900 } }
    },
    {
      name: "webkit",
      use: { ...devices["Desktop Safari"], viewport: { width: 1440, height: 900 } }
    }
  ]
});
