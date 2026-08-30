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
};

export async function listOpportunities(
  client: PoolClient,
  principal: AuthPrincipal,
  limit = 25
): Promise<OpportunitySummary[]> {
  const safeLimit = Math.min(Math.max(limit, 1), 100);
  const result = await client.query<OpportunitySummary>(
    `select id, social_account_id, market, platform, status, score,
            confidence, ranking_version, expires_at, created_at
       from growth.opportunities
      where workspace_id = $1
        and (expires_at is null or expires_at > now())
      order by score desc nulls last, created_at desc
      limit $2`,
    [principal.workspaceId, safeLimit]
  );
  return result.rows;
}

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
};

export async function listInsights(
  client: PoolClient,
  principal: AuthPrincipal,
  limit = 25
): Promise<InsightSummary[]> {
  const safeLimit = Math.min(Math.max(limit, 1), 100);
  const result = await client.query<InsightSummary>(
    `select id, social_account_id, state, claim, metric_definition,
            sample_size, confidence, logic_version, valid_from, expires_at, created_at
       from growth.insights
      where workspace_id = $1
        and valid_from <= now()
        and (expires_at is null or expires_at > now())
      order by created_at desc
      limit $2`,
    [principal.workspaceId, safeLimit]
  );
  return result.rows;
}
