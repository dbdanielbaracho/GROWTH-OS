import { performance } from "node:perf_hooks";
import { buildApp } from "../src/app.js";

type Probe = { statusCode: number; durationMs: number };

function percentile(values: number[], fraction: number) {
  const ordered = [...values].sort((a, b) => a - b);
  return ordered[Math.min(ordered.length - 1, Math.ceil(ordered.length * fraction) - 1)] ?? 0;
}

async function runBoundedLoad(
  name: string,
  total: number,
  concurrency: number,
  request: () => Promise<{ statusCode: number }>,
  expectedStatus: number,
  p95BudgetMs: number
) {
  const probes: Probe[] = [];
  let cursor = 0;
  async function worker() {
    while (true) {
      const index = cursor++;
      if (index >= total) return;
      const started = performance.now();
      const response = await request();
      probes.push({ statusCode: response.statusCode, durationMs: performance.now() - started });
    }
  }
  await Promise.all(Array.from({ length: concurrency }, () => worker()));
  const wrongStatus = probes.filter((probe) => probe.statusCode !== expectedStatus);
  const p95 = percentile(probes.map((probe) => probe.durationMs), 0.95);
  if (probes.length !== total || wrongStatus.length > 0 || p95 > p95BudgetMs) {
    throw new Error(`${name} failed: total=${probes.length}/${total} wrong_status=${wrongStatus.length} p95_ms=${p95.toFixed(2)} budget_ms=${p95BudgetMs}`);
  }
  console.log(`PASS: ${name} total=${total} concurrency=${concurrency} status=${expectedStatus} p95_ms=${p95.toFixed(2)} budget_ms=${p95BudgetMs}`);
}

const app = buildApp(false);
try {
  const ready = await app.inject({ method: "GET", url: "/health/ready" });
  if (ready.statusCode !== 200 || ready.json().database !== "ok") {
    throw new Error(`readiness baseline failed: ${ready.statusCode} ${ready.body}`);
  }

  await runBoundedLoad(
    "liveness burst remains available",
    300,
    30,
    () => app.inject({ method: "GET", url: "/health/live" }),
    200,
    250
  );
  await runBoundedLoad(
    "database readiness remains available under bounded concurrency",
    60,
    10,
    () => app.inject({ method: "GET", url: "/health/ready" }),
    200,
    1_500
  );
  await runBoundedLoad(
    "tenant API fails closed without a session under bounded concurrency",
    120,
    20,
    () => app.inject({ method: "GET", url: "/v1/opportunities" }),
    401,
    500
  );
} finally {
  await app.close();
}
