import assert from "node:assert/strict";
import test from "node:test";
import type { PoolClient } from "pg";
import { getIntelligenceModules } from "./intelligence-modules.js";

const principal = { userId: "user-1", workspaceId: "workspace-1", role: "owner", canPublish: true } as any;

type Scenario = {
  capabilities?: any[];
  opportunities?: any[];
  competitor?: any[];
  viral?: any[];
  experiments?: any[];
  variants?: Record<string, any[]>;
  details?: Record<string, any>;
};

function clientFor(s: Scenario): PoolClient {
  const query = async (sql: string, params?: unknown[]) => {
    if (sql.includes("list_intelligence_module_capabilities")) return { rows: s.capabilities ?? [] };
    if (sql.includes("list_competitor_intelligence_evidence")) return { rows: s.competitor ?? [] };
    if (sql.includes("list_viral_dna_evidence")) return { rows: s.viral ?? [] };
    if (sql.includes("growth.list_experiments")) return { rows: s.experiments ?? [] };
    if (sql.includes("growth.list_experiment_variants")) return { rows: s.variants?.[String(params?.[1])] ?? [] };
    if (sql.includes("from growth.opportunities o") && sql.includes("limit $2")) return { rows: s.opportunities ?? [] };
    if (sql.includes("where o.workspace_id = $1") && sql.includes("o.id = $2")) {
      const detail = s.details?.[String(params?.[1])];
      return { rows: detail ? [detail.opportunity] : [] };
    }
    if (sql.includes("from growth.opportunity_evidence")) {
      return { rows: s.details?.[String(params?.[1])]?.evidence ?? [] };
    }
    if (sql.includes("from growth.insights i") && sql.includes("i.social_account_id = $2")) return { rows: [] };
    throw new Error(`unexpected query: ${sql}`);
  };
  return { query } as unknown as PoolClient;
}

const providerRows = [
  { module_key: "global_trend_migration", platform: "instagram", status: "validation_required", evidence_ref: "meta-doc", evidence_status: "verified", kill_switch: true, limits: {} },
  { module_key: "competitor_intelligence", platform: "instagram", status: "validation_required", evidence_ref: "meta-doc", evidence_status: "verified", kill_switch: true, limits: {} },
  { module_key: "viral_dna", platform: "instagram", status: "validation_required", evidence_ref: "meta-doc", evidence_status: "verified", kill_switch: true, limits: {} }
];

test("competitor intelligence stays provider-limited without explicit competitor evidence", async () => {
  const result = await getIntelligenceModules(clientFor({ capabilities: providerRows }), principal);
  const module = result.modules.find((item) => item.key === "competitor_intelligence");
  assert.equal(module?.state, "provider_limited");
  assert.equal(module?.evidence_count, 0);
});

test("global trend migration requires external evidence across distinct dimensions", async () => {
  const opportunities = [
    { id: "o1", social_account_id: null, market: "US", platform: "instagram", status: "open", score: "1", confidence: {}, ranking_version: "v", expires_at: null, created_at: "2026-09-19", evidence_count: 1 },
    { id: "o2", social_account_id: null, market: "BR", platform: "youtube", status: "open", score: "1", confidence: {}, ranking_version: "v", expires_at: null, created_at: "2026-09-19", evidence_count: 1 }
  ];
  const details = {
    o1: { opportunity: opportunities[0], evidence: [{ id: "e1", source_class: "open", evidence_ref: "open-us", observed_at: null }] },
    o2: { opportunity: opportunities[1], evidence: [{ id: "e2", source_class: "licensed", evidence_ref: "licensed-br", observed_at: null }] }
  };
  const result = await getIntelligenceModules(clientFor({ capabilities: providerRows, opportunities, details }), principal);
  assert.equal(result.modules.find((item) => item.key === "global_trend_migration")?.state, "available");
});

test("viral DNA becomes available only with confirmed insight evidence and a measured winner", async () => {
  const result = await getIntelligenceModules(clientFor({
    capabilities: providerRows,
    viral: [{ insight_id: "i1", social_account_id: "a1", claim: "Hook A retained attention", evidence_type: "metric_observation", evidence_ref: "insight-evidence", source_class: "owned", created_at: "2026-09-19" }],
    experiments: [{ id: "x1", name: "Hook test", opportunity_id: null, hypothesis: "", decision_rule: "", status: "completed", variant_count: 1, created_at: "", updated_at: "" }],
    variants: { x1: [{ id: "v1", experiment_id: "x1", label: "Hook A", lineage: {}, status: "winner", created_at: "", latest_outcome: "winner", latest_evidence_ref: "experiment-evidence" }] }
  }), principal);
  const module = result.modules.find((item) => item.key === "viral_dna");
  assert.equal(module?.state, "available");
  assert.deepEqual(module?.evidence_refs.sort(), ["experiment-evidence", "insight-evidence"]);
});
