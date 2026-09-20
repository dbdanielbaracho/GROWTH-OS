from pathlib import Path


def write(path: str, content: str) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"marker missing in {path}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1))


write("apps/api/src/intelligence-modules.ts", r'''import type { PoolClient } from "pg";
import type { AuthPrincipal } from "./auth.js";
import { getOpportunityDetail, listOpportunities } from "./intelligence.js";
import { listExperiments, listExperimentVariants } from "./experiments.js";

export type IntelligenceModuleKey =
  | "global_trend_migration"
  | "competitor_intelligence"
  | "viral_dna";

export type IntelligenceModuleState =
  | "available"
  | "limited"
  | "insufficient_evidence"
  | "provider_limited";

export type IntelligenceProviderState = {
  platform: string;
  status: "enabled" | "disabled" | "degraded" | "validation_required";
  evidence_ref: string | null;
  evidence_status: string;
  kill_switch: boolean;
  limits: Record<string, unknown>;
};

export type IntelligenceModuleSignal = {
  label: string;
  detail: string;
  evidence_refs: string[];
};

export type IntelligenceModule = {
  key: IntelligenceModuleKey;
  title: string;
  state: IntelligenceModuleState;
  summary: string;
  evidence_count: number;
  evidence_refs: string[];
  signals: IntelligenceModuleSignal[];
  provider_states: IntelligenceProviderState[];
  limitations: string[];
};

type CapabilityRow = IntelligenceProviderState & { module_key: IntelligenceModuleKey };

type CompetitorEvidenceRow = {
  insight_id: string;
  social_account_id: string | null;
  claim: string;
  evidence_type: string;
  evidence_ref: string;
  source_class: string;
  created_at: string;
};

type ViralEvidenceRow = {
  insight_id: string;
  social_account_id: string | null;
  claim: string;
  evidence_type: string;
  evidence_ref: string;
  source_class: string;
  created_at: string;
};

function unique(values: string[]): string[] {
  return [...new Set(values.filter((value) => value.trim().length > 0))];
}

function providerStateFor(rows: CapabilityRow[], key: IntelligenceModuleKey) {
  return rows
    .filter((row) => row.module_key === key)
    .map(({ module_key: _moduleKey, ...row }) => row);
}

function providerLimited(rows: IntelligenceProviderState[]): boolean {
  return rows.length > 0 && rows.every((row) => row.status !== "enabled" || row.kill_switch);
}

async function listModuleCapabilities(client: PoolClient, principal: AuthPrincipal): Promise<CapabilityRow[]> {
  const result = await client.query<CapabilityRow>(
    "select * from growth.list_intelligence_module_capabilities($1)",
    [principal.workspaceId]
  );
  return result.rows;
}

async function listCompetitorEvidence(client: PoolClient, principal: AuthPrincipal): Promise<CompetitorEvidenceRow[]> {
  const result = await client.query<CompetitorEvidenceRow>(
    "select * from growth.list_competitor_intelligence_evidence($1, $2)",
    [principal.workspaceId, 100]
  );
  return result.rows;
}

async function listViralEvidence(client: PoolClient, principal: AuthPrincipal): Promise<ViralEvidenceRow[]> {
  const result = await client.query<ViralEvidenceRow>(
    "select * from growth.list_viral_dna_evidence($1, $2)",
    [principal.workspaceId, 100]
  );
  return result.rows;
}

export async function getIntelligenceModules(
  client: PoolClient,
  principal: AuthPrincipal
): Promise<{ generated_at: string; modules: IntelligenceModule[] }> {
  const [capabilities, opportunities, competitorEvidence, viralEvidence, experiments] = await Promise.all([
    listModuleCapabilities(client, principal),
    listOpportunities(client, principal, 100),
    listCompetitorEvidence(client, principal),
    listViralEvidence(client, principal),
    listExperiments(client, principal, 100)
  ]);

  const opportunityDetails = [];
  for (const opportunity of opportunities) {
    const detail = await getOpportunityDetail(client, principal, opportunity.id);
    if (detail) opportunityDetails.push(detail);
  }

  const externalClasses = new Set(["open", "licensed", "network"]);
  const trendSignals: IntelligenceModuleSignal[] = [];
  const trendEvidenceRefs: string[] = [];
  const trendDimensions = new Set<string>();

  for (const detail of opportunityDetails) {
    const external = detail.evidence.filter((item) => externalClasses.has(item.source_class));
    if (external.length === 0) continue;
    const refs = unique(external.map((item) => item.evidence_ref));
    trendEvidenceRefs.push(...refs);
    trendDimensions.add(`${detail.opportunity.market}|${detail.opportunity.platform}`);
    trendSignals.push({
      label: `${detail.opportunity.market} · ${detail.opportunity.platform}`,
      detail: `Stored opportunity with ${refs.length} external evidence reference${refs.length === 1 ? "" : "s"}.`,
      evidence_refs: refs
    });
  }

  const trendProviders = providerStateFor(capabilities, "global_trend_migration");
  const uniqueTrendRefs = unique(trendEvidenceRefs);
  const trendState: IntelligenceModuleState =
    uniqueTrendRefs.length >= 2 && trendDimensions.size >= 2
      ? "available"
      : uniqueTrendRefs.length > 0
        ? "limited"
        : providerLimited(trendProviders)
          ? "provider_limited"
          : "insufficient_evidence";

  const competitorProviders = providerStateFor(capabilities, "competitor_intelligence");
  const competitorRefs = unique(competitorEvidence.map((item) => item.evidence_ref));
  const competitorState: IntelligenceModuleState = competitorEvidence.length > 0
    ? "available"
    : providerLimited(competitorProviders)
      ? "provider_limited"
      : "insufficient_evidence";

  const winnerSignals: IntelligenceModuleSignal[] = [];
  const winnerRefs: string[] = [];
  for (const experiment of experiments) {
    const variants = await listExperimentVariants(client, principal, experiment.id);
    for (const variant of variants) {
      if (variant.latest_outcome !== "winner" || !variant.latest_evidence_ref) continue;
      winnerRefs.push(variant.latest_evidence_ref);
      winnerSignals.push({
        label: `Measured winner · ${variant.label}`,
        detail: experiment.name,
        evidence_refs: [variant.latest_evidence_ref]
      });
    }
  }

  const viralProviders = providerStateFor(capabilities, "viral_dna");
  const viralInsightRefs = unique(viralEvidence.map((item) => item.evidence_ref));
  const viralRefs = unique([...viralInsightRefs, ...winnerRefs]);
  const viralState: IntelligenceModuleState =
    viralInsightRefs.length > 0 && winnerRefs.length > 0
      ? "available"
      : viralRefs.length > 0
        ? "limited"
        : "insufficient_evidence";

  return {
    generated_at: new Date().toISOString(),
    modules: [
      {
        key: "global_trend_migration",
        title: "Global Trend Migration",
        state: trendState,
        summary: trendState === "available"
          ? "A trend is visible across multiple stored market/platform dimensions with external evidence."
          : trendState === "limited"
            ? "External evidence exists, but it does not yet span enough distinct market/platform dimensions to claim migration."
            : "No provider-permitted, cross-market evidence is strong enough to claim a global trend migration.",
        evidence_count: uniqueTrendRefs.length,
        evidence_refs: uniqueTrendRefs.slice(0, 20),
        signals: trendSignals.slice(0, 8),
        provider_states: trendProviders,
        limitations: [
          "Owned-account performance alone is not treated as a global trend.",
          "A migration claim requires external evidence across at least two distinct market/platform dimensions."
        ]
      },
      {
        key: "competitor_intelligence",
        title: "Competitor Intelligence",
        state: competitorState,
        summary: competitorEvidence.length > 0
          ? "Only explicitly labeled competitor evidence stored in this workspace is shown."
          : "No explicitly labeled competitor observation is stored in this workspace; Growth OS will not infer competitor metrics from owned-account data.",
        evidence_count: competitorRefs.length,
        evidence_refs: competitorRefs.slice(0, 20),
        signals: competitorEvidence.slice(0, 8).map((item) => ({
          label: item.claim,
          detail: `${item.evidence_type} · ${item.source_class}`,
          evidence_refs: [item.evidence_ref]
        })),
        provider_states: competitorProviders,
        limitations: [
          "Generic external evidence is not automatically reclassified as competitor evidence.",
          "Provider capabilities and commercial-use restrictions remain authoritative."
        ]
      },
      {
        key: "viral_dna",
        title: "Viral DNA",
        state: viralState,
        summary: viralState === "available"
          ? "Confirmed account insights and measured experiment winners overlap in the stored evidence, providing reusable creative learning."
          : viralState === "limited"
            ? "Some measured evidence exists, but Growth OS does not yet have both confirmed insight evidence and experiment-winner evidence."
            : "There is not enough measured evidence to describe reusable Viral DNA patterns.",
        evidence_count: viralRefs.length,
        evidence_refs: viralRefs.slice(0, 20),
        signals: [
          ...viralEvidence.slice(0, 6).map((item) => ({
            label: item.claim,
            detail: `Confirmed insight · ${item.evidence_type}`,
            evidence_refs: [item.evidence_ref]
          })),
          ...winnerSignals.slice(0, 6)
        ].slice(0, 10),
        provider_states: viralProviders,
        limitations: [
          "Repeated patterns are not described as causal unless a measured experiment supports them.",
          "No winner is accepted without a persisted experiment evidence reference."
        ]
      }
    ]
  };
}
''')

write("apps/api/src/intelligence-modules.test.ts", r'''import assert from "node:assert/strict";
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
''')

write("db/migrations/071_intelligence_module_capabilities.sql", r'''-- Growth OS — evidence-bounded intelligence module capability contract.
-- Forward-only migration 071. Provider capability rows describe what the
-- current adapters may truthfully claim; they do not manufacture intelligence.

BEGIN;
SET search_path = growth, public;

INSERT INTO growth.capabilities(
  id, platform, market, account_type, capability, status, required_scopes,
  limits, media_constraints, app_review_status, provider_api_version,
  validated_at, evidence_ref, evidence_status, adapter_version, kill_switch, updated_at
)
VALUES
  (gen_random_uuid(),'instagram','GLOBAL','professional','intelligence_global_trend_migration','validation_required',
   ARRAY['instagram_business_basic'],
   '{"reason":"external cross-market discovery is not implemented in the current Instagram Login adapter"}'::jsonb,
   '{}'::jsonb,'not_submitted','instagram-api-with-instagram-login','2026-09-19T00:00:00Z',
   'https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api','verified','intelligence-v0.1',true,now()),
  (gen_random_uuid(),'instagram','GLOBAL','professional','intelligence_competitor_intelligence','validation_required',
   ARRAY['instagram_business_basic'],
   '{"reason":"competitor evidence requires an explicitly reviewed provider-permitted discovery path"}'::jsonb,
   '{}'::jsonb,'not_submitted','instagram-api-with-instagram-login','2026-09-19T00:00:00Z',
   'https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api','verified','intelligence-v0.1',true,now()),
  (gen_random_uuid(),'instagram','GLOBAL','professional','intelligence_viral_dna','validation_required',
   ARRAY['instagram_business_basic','instagram_business_manage_insights'],
   '{"reason":"module can use stored owned evidence but provider analytics remain permission/app-review bounded"}'::jsonb,
   '{}'::jsonb,'not_submitted','instagram-api-with-instagram-login','2026-09-19T00:00:00Z',
   'https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api','verified','intelligence-v0.1',true,now()),

  (gen_random_uuid(),'youtube','GLOBAL','channel','intelligence_global_trend_migration','validation_required',
   '{}'::text[],
   '{"reason":"public metadata/stats exist, but cross-target trend discovery and ingestion are not implemented"}'::jsonb,
   '{}'::jsonb,NULL,'2026-09','2026-09-19T00:00:00Z',
   'https://developers.google.com/youtube/v3/docs/channels','verified','intelligence-v0.1',true,now()),
  (gen_random_uuid(),'youtube','GLOBAL','channel','intelligence_competitor_intelligence','validation_required',
   '{}'::text[],
   '{"reason":"public channel stats exist, but arbitrary competitor target ingestion is not implemented"}'::jsonb,
   '{}'::jsonb,NULL,'2026-09','2026-09-19T00:00:00Z',
   'https://developers.google.com/youtube/v3/docs/channels','verified','intelligence-v0.1',true,now()),
  (gen_random_uuid(),'youtube','GLOBAL','channel','intelligence_viral_dna','validation_required',
   ARRAY['https://www.googleapis.com/auth/yt-analytics.readonly'],
   '{"reason":"owned measured learning is supported only after authorized analytics are available"}'::jsonb,
   '{}'::jsonb,'not_submitted','2026-09','2026-09-19T00:00:00Z',
   'https://developers.google.com/youtube/analytics','verified','intelligence-v0.1',true,now()),

  (gen_random_uuid(),'tiktok','GLOBAL','commercial','intelligence_global_trend_migration','disabled',
   '{}'::text[],
   '{"reason":"TikTok Research Tools are not available to creators, advertisers, or commercial users"}'::jsonb,
   '{}'::jsonb,NULL,'research-api-2026-09','2026-09-19T00:00:00Z',
   'https://developers.tiktok.com/doc/research-api-faq','verified','intelligence-v0.1',true,now()),
  (gen_random_uuid(),'tiktok','GLOBAL','commercial','intelligence_competitor_intelligence','disabled',
   '{}'::text[],
   '{"reason":"no approved commercial competitor-research connector is configured"}'::jsonb,
   '{}'::jsonb,NULL,'research-api-2026-09','2026-09-19T00:00:00Z',
   'https://developers.tiktok.com/doc/research-api-faq','verified','intelligence-v0.1',true,now()),
  (gen_random_uuid(),'tiktok','GLOBAL','commercial','intelligence_viral_dna','disabled',
   '{}'::text[],
   '{"reason":"no approved commercial research connector is configured"}'::jsonb,
   '{}'::jsonb,NULL,'research-api-2026-09','2026-09-19T00:00:00Z',
   'https://developers.tiktok.com/doc/research-api-faq','verified','intelligence-v0.1',true,now())
ON CONFLICT (platform,market,account_type,capability) DO UPDATE
SET status = EXCLUDED.status,
    required_scopes = EXCLUDED.required_scopes,
    limits = EXCLUDED.limits,
    media_constraints = EXCLUDED.media_constraints,
    app_review_status = EXCLUDED.app_review_status,
    provider_api_version = EXCLUDED.provider_api_version,
    validated_at = EXCLUDED.validated_at,
    evidence_ref = EXCLUDED.evidence_ref,
    evidence_status = EXCLUDED.evidence_status,
    adapter_version = EXCLUDED.adapter_version,
    kill_switch = EXCLUDED.kill_switch,
    updated_at = now();

CREATE OR REPLACE FUNCTION growth.list_intelligence_module_capabilities(p_workspace_id uuid)
RETURNS TABLE(
  module_key text,
  platform text,
  status text,
  evidence_ref text,
  evidence_status text,
  kill_switch boolean,
  limits jsonb
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id) THEN
    RAISE EXCEPTION 'intelligence capability workspace context mismatch';
  END IF;

  RETURN QUERY
  SELECT replace(c.capability, 'intelligence_', '') AS module_key,
         c.platform, c.status, c.evidence_ref, c.evidence_status, c.kill_switch, c.limits
    FROM growth.capabilities c
   WHERE c.capability IN (
     'intelligence_global_trend_migration',
     'intelligence_competitor_intelligence',
     'intelligence_viral_dna'
   )
   ORDER BY c.capability, c.platform;
END;
$$;

CREATE OR REPLACE FUNCTION growth.list_competitor_intelligence_evidence(
  p_workspace_id uuid,
  p_limit integer DEFAULT 100
)
RETURNS TABLE(
  insight_id uuid,
  social_account_id uuid,
  claim text,
  evidence_type text,
  evidence_ref text,
  source_class text,
  created_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id) THEN
    RAISE EXCEPTION 'competitor intelligence workspace context mismatch';
  END IF;

  RETURN QUERY
  SELECT i.id, i.social_account_id, i.claim, ie.evidence_type, ie.evidence_ref,
         ie.source_class, ie.created_at
    FROM growth.insights i
    JOIN growth.insight_evidence ie
      ON ie.workspace_id = i.workspace_id AND ie.insight_id = i.id
   WHERE i.workspace_id = p_workspace_id
     AND i.valid_from <= now()
     AND (i.expires_at IS NULL OR i.expires_at > now())
     AND lower(ie.evidence_type) IN (
       'competitor_metric', 'competitor_observation', 'business_discovery', 'public_channel_stats'
     )
   ORDER BY ie.created_at DESC, ie.id
   LIMIT greatest(1, least(coalesce(p_limit,100),100));
END;
$$;

CREATE OR REPLACE FUNCTION growth.list_viral_dna_evidence(
  p_workspace_id uuid,
  p_limit integer DEFAULT 100
)
RETURNS TABLE(
  insight_id uuid,
  social_account_id uuid,
  claim text,
  evidence_type text,
  evidence_ref text,
  source_class text,
  created_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id) THEN
    RAISE EXCEPTION 'viral DNA workspace context mismatch';
  END IF;

  RETURN QUERY
  SELECT i.id, i.social_account_id, i.claim, ie.evidence_type, ie.evidence_ref,
         ie.source_class, ie.created_at
    FROM growth.insights i
    JOIN growth.insight_evidence ie
      ON ie.workspace_id = i.workspace_id AND ie.insight_id = i.id
   WHERE i.workspace_id = p_workspace_id
     AND i.state = 'confirmed_account'
     AND i.valid_from <= now()
     AND (i.expires_at IS NULL OR i.expires_at > now())
   ORDER BY ie.weight DESC NULLS LAST, ie.created_at DESC, ie.id
   LIMIT greatest(1, least(coalesce(p_limit,100),100));
END;
$$;

ALTER FUNCTION growth.list_intelligence_module_capabilities(uuid) OWNER TO growth_migrator;
ALTER FUNCTION growth.list_competitor_intelligence_evidence(uuid,integer) OWNER TO growth_migrator;
ALTER FUNCTION growth.list_viral_dna_evidence(uuid,integer) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.list_intelligence_module_capabilities(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.list_competitor_intelligence_evidence(uuid,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.list_viral_dna_evidence(uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.list_intelligence_module_capabilities(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.list_competitor_intelligence_evidence(uuid,integer) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.list_viral_dna_evidence(uuid,integer) TO app_runtime;

COMMIT;
''')

write("db/tests/071_intelligence_module_capabilities.sql", r'''-- Catalog-only gate for evidence-bounded intelligence modules.
\set ON_ERROR_STOP on

DO $$
DECLARE
  module_rows integer;
BEGIN
  SELECT count(*) INTO module_rows
    FROM growth.capabilities
   WHERE capability IN (
     'intelligence_global_trend_migration',
     'intelligence_competitor_intelligence',
     'intelligence_viral_dna'
   );
  IF module_rows <> 9 THEN
    RAISE EXCEPTION 'expected 9 intelligence module capability rows, found %', module_rows;
  END IF;
  IF EXISTS (
    SELECT 1 FROM growth.capabilities
     WHERE capability LIKE 'intelligence_%'
       AND (evidence_ref IS NULL OR btrim(evidence_ref) = '')
  ) THEN
    RAISE EXCEPTION 'intelligence module capability is missing evidence_ref';
  END IF;
  IF to_regprocedure('growth.list_intelligence_module_capabilities(uuid)') IS NULL
     OR to_regprocedure('growth.list_competitor_intelligence_evidence(uuid,integer)') IS NULL
     OR to_regprocedure('growth.list_viral_dna_evidence(uuid,integer)') IS NULL THEN
    RAISE EXCEPTION 'intelligence module helper is missing';
  END IF;
  IF has_function_privilege('public','growth.list_intelligence_module_capabilities(uuid)','EXECUTE')
     OR has_function_privilege('public','growth.list_competitor_intelligence_evidence(uuid,integer)','EXECUTE')
     OR has_function_privilege('public','growth.list_viral_dna_evidence(uuid,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'public must not execute intelligence module helpers';
  END IF;
  IF NOT has_function_privilege('app_runtime','growth.list_intelligence_module_capabilities(uuid)','EXECUTE')
     OR NOT has_function_privilege('app_runtime','growth.list_competitor_intelligence_evidence(uuid,integer)','EXECUTE')
     OR NOT has_function_privilege('app_runtime','growth.list_viral_dna_evidence(uuid,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'app_runtime is missing intelligence helper execute privilege';
  END IF;
END $$;
''')

write("apps/web/src/intelligence-modules.tsx", r'''import React, { useCallback, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  fetchAuthSession,
  fetchIntelligenceModules,
  RadarApiError,
  type IntelligenceModule,
  type IntelligenceModuleState
} from "./api.js";
import "./intelligence-modules.css";

function stateLabel(state: IntelligenceModuleState) {
  if (state === "available") return "Available";
  if (state === "limited") return "Limited evidence";
  if (state === "provider_limited") return "Provider limited";
  return "Insufficient evidence";
}

function ModuleCard({ module }: { module: IntelligenceModule }) {
  return (
    <article className="intelligence-module-card">
      <div className="intelligence-module-heading">
        <div>
          <p className="intelligence-module-kicker">Evidence-bounded module</p>
          <h3>{module.title}</h3>
        </div>
        <span className={`intelligence-state state-${module.state}`}>{stateLabel(module.state)}</span>
      </div>
      <p>{module.summary}</p>
      <div className="intelligence-stat"><strong>{module.evidence_count}</strong><span>stored evidence refs</span></div>

      {module.signals.length > 0 ? (
        <div className="intelligence-signals">
          {module.signals.map((signal, index) => (
            <div className="intelligence-signal" key={`${module.key}-${index}`}>
              <strong>{signal.label}</strong>
              <span>{signal.detail}</span>
              {signal.evidence_refs.map((ref) => <code key={ref}>{ref}</code>)}
            </div>
          ))}
        </div>
      ) : (
        <p className="intelligence-empty">No qualifying stored signal is being substituted with synthetic data.</p>
      )}

      <details className="intelligence-boundaries">
        <summary>Provider and evidence boundaries</summary>
        <div className="intelligence-provider-list">
          {module.provider_states.map((provider) => (
            <div key={`${module.key}-${provider.platform}`}>
              <strong>{provider.platform}</strong>
              <span>{provider.status}{provider.kill_switch ? " · kill switch on" : ""}</span>
              {provider.evidence_ref && <code>{provider.evidence_ref}</code>}
            </div>
          ))}
        </div>
        <ul>{module.limitations.map((item) => <li key={item}>{item}</li>)}</ul>
      </details>
    </article>
  );
}

function IntelligenceModulesPanel() {
  const authGeneration = useRef(0);
  const [authenticated, setAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const [modules, setModules] = useState<IntelligenceModule[]>([]);
  const [message, setMessage] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    const generation = authGeneration.current;
    try {
      await fetchAuthSession();
      if (generation !== authGeneration.current) return;
      setAuthenticated(true);
      const rows = await fetchIntelligenceModules();
      if (generation !== authGeneration.current) return;
      setModules(rows);
      setMessage(null);
    } catch (error) {
      if (generation !== authGeneration.current) return;
      if (error instanceof RadarApiError && error.httpStatus === 401) {
        setAuthenticated(false);
        setModules([]);
      } else {
        setMessage("Intelligence modules could not load. No synthetic module output was substituted.");
      }
    } finally {
      if (generation === authGeneration.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    const onAuthChange = (event: Event) => {
      authGeneration.current += 1;
      setAuthenticated(false);
      setModules([]);
      setMessage(null);
      setLoading(Boolean((event as CustomEvent<{ authenticated?: boolean }>).detail?.authenticated));
      if ((event as CustomEvent<{ authenticated?: boolean }>).detail?.authenticated) void refresh();
    };
    window.addEventListener("growth-os:auth-change", onAuthChange);
    return () => window.removeEventListener("growth-os:auth-change", onAuthChange);
  }, [refresh]);

  useEffect(() => { void refresh(); }, [refresh]);

  if (!authenticated) return null;

  return (
    <section className="intelligence-modules-shell" aria-labelledby="intelligence-modules-title">
      <div className="intelligence-modules-title-row">
        <div>
          <p className="intelligence-module-kicker">Growth Intelligence · provider aware</p>
          <h2 id="intelligence-modules-title">What the evidence can support now</h2>
          <p>Trend migration, competitor intelligence and Viral DNA stay bounded by stored evidence and provider capability. A missing data path is shown as a limitation, never filled with estimates.</p>
        </div>
        <button type="button" onClick={() => void refresh()} disabled={loading}>{loading ? "Checking…" : "Refresh evidence"}</button>
      </div>
      {message && <p className="intelligence-error" role="alert">{message}</p>}
      <div className="intelligence-modules-grid">
        {modules.map((module) => <ModuleCard key={module.key} module={module} />)}
      </div>
    </section>
  );
}

const root = document.getElementById("intelligence-modules-root");
if (root) createRoot(root).render(<IntelligenceModulesPanel />);
''')

write("apps/web/src/intelligence-modules.css", r'''.intelligence-modules-shell {
  width: min(1180px, calc(100% - 40px));
  margin: 36px auto 52px;
  padding: 28px;
  border: 1px solid rgba(20, 24, 31, 0.13);
  border-radius: 24px;
  background: rgba(255, 255, 255, 0.94);
  box-sizing: border-box;
}

.intelligence-modules-title-row {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 24px;
  margin-bottom: 24px;
}

.intelligence-modules-title-row h2,
.intelligence-module-card h3 { margin: 4px 0 8px; }
.intelligence-modules-title-row p { max-width: 760px; margin: 0; line-height: 1.55; }
.intelligence-module-kicker { margin: 0; font-size: .73rem; letter-spacing: .12em; text-transform: uppercase; opacity: .62; }
.intelligence-modules-title-row button { white-space: nowrap; border: 1px solid rgba(20,24,31,.18); background: white; border-radius: 999px; padding: 10px 16px; cursor: pointer; }
.intelligence-modules-title-row button:disabled { opacity: .55; cursor: default; }

.intelligence-modules-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 16px; }
.intelligence-module-card { min-width: 0; padding: 20px; border-radius: 18px; background: #f6f7f8; border: 1px solid rgba(20,24,31,.08); }
.intelligence-module-heading { display: flex; justify-content: space-between; gap: 12px; align-items: flex-start; }
.intelligence-state { flex: 0 0 auto; border-radius: 999px; padding: 6px 9px; font-size: .72rem; font-weight: 650; border: 1px solid rgba(20,24,31,.14); background: white; }
.state-available { border-style: solid; }
.state-limited, .state-provider_limited, .state-insufficient_evidence { border-style: dashed; }
.intelligence-stat { display: flex; gap: 7px; align-items: baseline; margin: 18px 0; }
.intelligence-stat strong { font-size: 1.65rem; }
.intelligence-stat span { font-size: .82rem; opacity: .65; }
.intelligence-signals { display: grid; gap: 9px; }
.intelligence-signal, .intelligence-provider-list > div { min-width: 0; display: grid; gap: 4px; padding: 10px; border-radius: 12px; background: white; }
.intelligence-signal span, .intelligence-provider-list span { font-size: .82rem; opacity: .72; }
.intelligence-signal code, .intelligence-provider-list code { overflow-wrap: anywhere; white-space: normal; font-size: .72rem; }
.intelligence-empty { padding: 12px; border-radius: 12px; background: white; font-size: .84rem; line-height: 1.45; }
.intelligence-boundaries { margin-top: 14px; }
.intelligence-boundaries summary { cursor: pointer; font-weight: 650; font-size: .84rem; }
.intelligence-provider-list { display: grid; gap: 7px; margin-top: 10px; }
.intelligence-boundaries ul { margin: 10px 0 0; padding-left: 19px; font-size: .78rem; line-height: 1.5; }
.intelligence-error { padding: 12px 14px; border-radius: 12px; background: #fff4f2; }

@media (max-width: 900px) {
  .intelligence-modules-grid { grid-template-columns: 1fr; }
}
@media (max-width: 560px) {
  .intelligence-modules-shell { width: min(100% - 20px, 1180px); margin: 24px auto 36px; padding: 18px; border-radius: 18px; }
  .intelligence-modules-title-row { flex-direction: column; }
  .intelligence-modules-title-row button { width: 100%; }
  .intelligence-module-heading { flex-direction: column; }
}
''')

# Experiment rows already carry latest outcome columns from migration 063.
replace_once(
    "apps/api/src/experiments.ts",
    '  status: "candidate" | "active" | "winner" | "loser" | "archived";\n  created_at: string;\n};',
    '  status: "candidate" | "active" | "winner" | "loser" | "archived";\n  created_at: string;\n  latest_outcome?: "winner" | "loser" | "inconclusive" | null;\n  latest_evidence_ref?: string | null;\n  feedback_created_at?: string | null;\n};'
)

replace_once(
    "apps/api/src/app.ts",
    'import { getOpportunityDetail, listInsights, listOpportunities } from "./intelligence.js";\n',
    'import { getOpportunityDetail, listInsights, listOpportunities } from "./intelligence.js";\nimport { getIntelligenceModules } from "./intelligence-modules.js";\n'
)

replace_once(
    "apps/api/src/app.ts",
    '\n\n\n  app.post("/v1/copilot/query", async (request, reply) => {',
    '''\n\n  app.get("/v1/intelligence/modules", async (request, reply) => {\n    const principal = await requestPrincipal(request, reply);\n    if (!principal) return;\n\n    try {\n      const result = await withTenantTransaction(principal, (client) =>\n        getIntelligenceModules(client, principal)\n      );\n      return { status: "ok", ...result };\n    } catch (error) {\n      app.log.error(error);\n      const mapped = databaseStatus(error);\n      return reply.code(mapped.code).send({ status: mapped.status });\n    }\n  });\n\n\n  app.post("/v1/copilot/query", async (request, reply) => {'''
)

# Web API additions.
p = Path("apps/web/src/api.ts")
text = p.read_text()
if "export type IntelligenceModuleState" not in text:
    text += r'''

export type IntelligenceModuleState = "available" | "limited" | "insufficient_evidence" | "provider_limited";
export type IntelligenceProviderState = {
  platform: string;
  status: "enabled" | "disabled" | "degraded" | "validation_required";
  evidence_ref: string | null;
  evidence_status: string;
  kill_switch: boolean;
  limits: Record<string, unknown>;
};
export type IntelligenceModule = {
  key: "global_trend_migration" | "competitor_intelligence" | "viral_dna";
  title: string;
  state: IntelligenceModuleState;
  summary: string;
  evidence_count: number;
  evidence_refs: string[];
  signals: Array<{ label: string; detail: string; evidence_refs: string[] }>;
  provider_states: IntelligenceProviderState[];
  limitations: string[];
};

export async function fetchIntelligenceModules(): Promise<IntelligenceModule[]> {
  const response = await requestJson<{ status: "ok"; generated_at: string; modules: IntelligenceModule[] }>("/v1/intelligence/modules");
  return response.modules;
}
'''
    p.write_text(text)

replace_once(
    "apps/web/index.html",
    '    <div id="copilot-panel-root"></div>\n    <div id="creative-studio-root"></div>',
    '    <div id="copilot-panel-root"></div>\n    <div id="intelligence-modules-root"></div>\n    <div id="creative-studio-root"></div>'
)
replace_once(
    "apps/web/index.html",
    '    <script type="module" src="/src/copilot-panel.tsx"></script>\n    <script type="module" src="/src/creative-studio.tsx"></script>',
    '    <script type="module" src="/src/copilot-panel.tsx"></script>\n    <script type="module" src="/src/intelligence-modules.tsx"></script>\n    <script type="module" src="/src/creative-studio.tsx"></script>'
)

# Production migration registry.
replace_once(
    "db/scripts/apply-production-migrations.mjs",
    "  {\n    file: '070_scheduled_publication_dispatch.sql',\n    present: async () => {\n      const scheduleSignature = 'growth.schedule_publication_intent(uuid,uuid,timestamptz)';\n      const dispatchSignature = 'growth.enqueue_due_scheduled_publications(uuid,timestamptz,integer)';\n      if (!(await functionExists(scheduleSignature)) || !(await functionExists(dispatchSignature))) return false;\n      const result = await client.query(`\n        select\n          has_function_privilege('app_runtime', $1::regprocedure, 'EXECUTE')\n          and has_function_privilege('growth_worker', $2::regprocedure, 'EXECUTE')\n          and not has_function_privilege('public', $1::regprocedure, 'EXECUTE')\n          and not has_function_privilege('public', $2::regprocedure, 'EXECUTE')\n          as present\n      `, [scheduleSignature, dispatchSignature]);\n      return result.rows[0]?.present === true;\n    },\n  },\n\n];",
    "  {\n    file: '070_scheduled_publication_dispatch.sql',\n    present: async () => {\n      const scheduleSignature = 'growth.schedule_publication_intent(uuid,uuid,timestamptz)';\n      const dispatchSignature = 'growth.enqueue_due_scheduled_publications(uuid,timestamptz,integer)';\n      if (!(await functionExists(scheduleSignature)) || !(await functionExists(dispatchSignature))) return false;\n      const result = await client.query(`\n        select\n          has_function_privilege('app_runtime', $1::regprocedure, 'EXECUTE')\n          and has_function_privilege('growth_worker', $2::regprocedure, 'EXECUTE')\n          and not has_function_privilege('public', $1::regprocedure, 'EXECUTE')\n          and not has_function_privilege('public', $2::regprocedure, 'EXECUTE')\n          as present\n      `, [scheduleSignature, dispatchSignature]);\n      return result.rows[0]?.present === true;\n    },\n  },\n  {\n    file: '071_intelligence_module_capabilities.sql',\n    present: async () => {\n      if (!(await functionExists('growth.list_intelligence_module_capabilities(uuid)'))\n          || !(await functionExists('growth.list_competitor_intelligence_evidence(uuid,integer)'))\n          || !(await functionExists('growth.list_viral_dna_evidence(uuid,integer)'))) return false;\n      const result = await client.query(`\n        select count(*) = 9\n          and count(*) filter (where evidence_ref is not null and btrim(evidence_ref) <> '') = 9\n          as present\n          from growth.capabilities\n         where capability in (\n           'intelligence_global_trend_migration',\n           'intelligence_competitor_intelligence',\n           'intelligence_viral_dna'\n         )\n      `);\n      return result.rows[0]?.present === true;\n    },\n  },\n\n];"
)

# Browser API mock + product proof.
replace_once(
    "tests/browser/growth-os.browser.spec.ts",
    '      "/v1/commercial/entitlements", "/v1/commercial/enterprise-policy",\n      "/v1/creative/requests",',
    '      "/v1/commercial/entitlements", "/v1/commercial/enterprise-policy", "/v1/intelligence/modules",\n      "/v1/creative/requests",'
)
replace_once(
    "tests/browser/growth-os.browser.spec.ts",
    '    if (mode === "authenticated" && path === "/v1/content") {\n      return json(route, 200, { status: "ok", content });\n    }',
    '''    if (mode === "authenticated" && path === "/v1/intelligence/modules") {\n      return json(route, 200, {\n        status: "ok", generated_at: "2026-09-19T12:00:00.000Z", modules: [\n          { key: "global_trend_migration", title: "Global Trend Migration", state: "limited", summary: "Controlled browser fixture has external evidence in one dimension only.", evidence_count: 1, evidence_refs: ["browser-quality-trend-evidence"], signals: [{ label: "US · instagram", detail: "One controlled external reference.", evidence_refs: ["browser-quality-trend-evidence"] }], provider_states: [{ platform: "instagram", status: "validation_required", evidence_ref: "browser-quality-provider-doc", evidence_status: "verified", kill_switch: true, limits: {} }], limitations: ["Requires two dimensions."] },\n          { key: "competitor_intelligence", title: "Competitor Intelligence", state: "provider_limited", summary: "No explicit competitor observation is stored.", evidence_count: 0, evidence_refs: [], signals: [], provider_states: [{ platform: "instagram", status: "validation_required", evidence_ref: "browser-quality-provider-doc", evidence_status: "verified", kill_switch: true, limits: {} }], limitations: ["No inferred competitor metrics."] },\n          { key: "viral_dna", title: "Viral DNA", state: "insufficient_evidence", summary: "No measured winner is stored.", evidence_count: 0, evidence_refs: [], signals: [], provider_states: [{ platform: "instagram", status: "validation_required", evidence_ref: "browser-quality-provider-doc", evidence_status: "verified", kill_switch: true, limits: {} }], limitations: ["No causal claim without measured evidence."] }\n        ]\n      });\n    }\n\n    if (mode === "authenticated" && path === "/v1/content") {\n      return json(route, 200, { status: "ok", content });\n    }'''
)

p = Path("tests/browser/growth-os.browser.spec.ts")
text = p.read_text()
if 'test("evidence-bounded intelligence modules expose provider limits without synthetic signals"' not in text:
    marker = '\ntest("Creative Studio and Publication Calendar are accessible fail-closed product surfaces", async ({ page }) => {'
    addition = r'''

test("evidence-bounded intelligence modules expose provider limits without synthetic signals", async ({ page }) => {
  const unhandled = await mockApi(page, "authenticated");
  await page.goto("/");

  const region = page.getByRole("region", { name: "What the evidence can support now" });
  await expect(region).toBeVisible();
  await expect(region.getByRole("heading", { name: "Global Trend Migration" })).toBeVisible();
  await expect(region.getByRole("heading", { name: "Competitor Intelligence" })).toBeVisible();
  await expect(region.getByRole("heading", { name: "Viral DNA" })).toBeVisible();
  await expect(region.getByText("Provider limited", { exact: true })).toBeVisible();
  await expect(region.getByText("browser-quality-trend-evidence", { exact: true })).toBeVisible();
  await expect(region.getByText("No qualifying stored signal is being substituted with synthetic data.").first()).toBeVisible();

  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
  expect(unhandled).toEqual([]);
});
'''
    if marker not in text:
        raise SystemExit("browser insertion marker missing")
    p.write_text(text.replace(marker, addition + marker, 1))
