import type { PoolClient } from "pg";
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
