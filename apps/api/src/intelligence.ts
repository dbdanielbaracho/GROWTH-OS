import type { PoolClient } from "pg";
import type { AuthPrincipal } from "./auth.js";

export type OpportunitySummary = {
  id: string;
  social_account_id: string | null;
  market: string;
  platform: string;
  status: string;
  score: string | null;
  confidence: unknown;
  ranking_version: string;
  expires_at: string | null;
  created_at: string;
  evidence_count: number;
};

export type OpportunityEvidence = {
  id: string;
  source_class: string;
  evidence_ref: string;
  observed_at: string | null;
};

export type InsightEvidence = {
  id: string;
  evidence_type: string;
  evidence_ref: string;
  source_class: "owned" | "open" | "licensed" | "network" | "general";
  weight: string | null;
  created_at: string;
};

export type InsightSummary = {
  id: string;
  social_account_id: string | null;
  state: "confirmed_account" | "account_hypothesis" | "general_practice" | "insufficient_signal";
  claim: string;
  metric_definition: unknown;
  sample_size: number | null;
  confidence: unknown;
  logic_version: string;
  valid_from: string;
  expires_at: string | null;
  created_at: string;
  evidence_count: number;
};

export type RelatedInsight = InsightSummary & {
  evidence: InsightEvidence[];
};

export type OpportunityDetail = {
  opportunity: OpportunitySummary;
  evidence: OpportunityEvidence[];
  related_insights: RelatedInsight[];
};

export async function listOpportunities(
  client: PoolClient,
  principal: AuthPrincipal,
  limit = 25
): Promise<OpportunitySummary[]> {
  const safeLimit = Math.min(Math.max(limit, 1), 100);
  const result = await client.query<OpportunitySummary>(
    `select o.id, o.social_account_id, o.market, o.platform, o.status, o.score,
            o.confidence, o.ranking_version, o.expires_at, o.created_at,
            (select count(*)::int
               from growth.opportunity_evidence oe
              where oe.workspace_id = o.workspace_id
                and oe.opportunity_id = o.id) as evidence_count
       from growth.opportunities o
      where o.workspace_id = $1
        and (o.expires_at is null or o.expires_at > now())
      order by o.score desc nulls last, o.created_at desc
      limit $2`,
    [principal.workspaceId, safeLimit]
  );
  return result.rows;
}

export async function listInsights(
  client: PoolClient,
  principal: AuthPrincipal,
  limit = 25
): Promise<InsightSummary[]> {
  const safeLimit = Math.min(Math.max(limit, 1), 100);
  const result = await client.query<InsightSummary>(
    `select i.id, i.social_account_id, i.state, i.claim, i.metric_definition,
            i.sample_size, i.confidence, i.logic_version, i.valid_from, i.expires_at, i.created_at,
            (select count(*)::int
               from growth.insight_evidence ie
              where ie.workspace_id = i.workspace_id
                and ie.insight_id = i.id) as evidence_count
       from growth.insights i
      where i.workspace_id = $1
        and i.valid_from <= now()
        and (i.expires_at is null or i.expires_at > now())
      order by i.created_at desc
      limit $2`,
    [principal.workspaceId, safeLimit]
  );
  return result.rows;
}

export async function getOpportunityDetail(
  client: PoolClient,
  principal: AuthPrincipal,
  opportunityId: string
): Promise<OpportunityDetail | null> {
  const opportunityResult = await client.query<OpportunitySummary>(
    `select o.id, o.social_account_id, o.market, o.platform, o.status, o.score,
            o.confidence, o.ranking_version, o.expires_at, o.created_at,
            (select count(*)::int
               from growth.opportunity_evidence oe
              where oe.workspace_id = o.workspace_id
                and oe.opportunity_id = o.id) as evidence_count
       from growth.opportunities o
      where o.workspace_id = $1
        and o.id = $2
        and (o.expires_at is null or o.expires_at > now())
      limit 1`,
    [principal.workspaceId, opportunityId]
  );

  const opportunity = opportunityResult.rows[0];
  if (!opportunity) return null;

  const evidenceResult = await client.query<OpportunityEvidence>(
    `select id, source_class, evidence_ref, observed_at
       from growth.opportunity_evidence
      where workspace_id = $1
        and opportunity_id = $2
      order by observed_at desc nulls last, id
      limit 100`,
    [principal.workspaceId, opportunityId]
  );

  if (!opportunity.social_account_id) {
    return {
      opportunity,
      evidence: evidenceResult.rows,
      related_insights: []
    };
  }

  const insightsResult = await client.query<InsightSummary>(
    `select i.id, i.social_account_id, i.state, i.claim, i.metric_definition,
            i.sample_size, i.confidence, i.logic_version, i.valid_from, i.expires_at, i.created_at,
            (select count(*)::int
               from growth.insight_evidence ie
              where ie.workspace_id = i.workspace_id
                and ie.insight_id = i.id) as evidence_count
       from growth.insights i
      where i.workspace_id = $1
        and i.social_account_id = $2
        and i.valid_from <= now()
        and (i.expires_at is null or i.expires_at > now())
      order by case i.state
                 when 'confirmed_account' then 1
                 when 'account_hypothesis' then 2
                 when 'general_practice' then 3
                 else 4
               end,
               i.created_at desc
      limit 20`,
    [principal.workspaceId, opportunity.social_account_id]
  );

  const insightIds = insightsResult.rows.map((insight) => insight.id);
  let insightEvidenceRows: Array<InsightEvidence & { insight_id: string }> = [];

  if (insightIds.length > 0) {
    const insightEvidenceResult = await client.query<InsightEvidence & { insight_id: string }>(
      `with ranked as (
         select insight_id, id, evidence_type, evidence_ref, source_class, weight, created_at,
                row_number() over (
                  partition by insight_id
                  order by weight desc nulls last, created_at desc, id
                ) as evidence_rank
           from growth.insight_evidence
          where workspace_id = $1
            and insight_id = any($2::uuid[])
       )
       select insight_id, id, evidence_type, evidence_ref, source_class, weight, created_at
         from ranked
        where evidence_rank <= 5
        order by insight_id, evidence_rank`,
      [principal.workspaceId, insightIds]
    );
    insightEvidenceRows = insightEvidenceResult.rows;
  }

  const evidenceByInsight = new Map<string, InsightEvidence[]>();
  for (const row of insightEvidenceRows) {
    const { insight_id, ...evidence } = row;
    const current = evidenceByInsight.get(insight_id) ?? [];
    current.push(evidence);
    evidenceByInsight.set(insight_id, current);
  }

  return {
    opportunity,
    evidence: evidenceResult.rows,
    related_insights: insightsResult.rows.map((insight) => ({
      ...insight,
      evidence: evidenceByInsight.get(insight.id) ?? []
    }))
  };
}
