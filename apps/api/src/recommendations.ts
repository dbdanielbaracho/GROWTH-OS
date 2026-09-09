import type { PoolClient } from "pg";
import type { AuthPrincipal } from "./auth.js";

export type RecommendationActionCode = "draft_content" | "review_evidence" | "plan_experiment";
export type RecommendationFeedback = "accepted" | "dismissed" | "completed" | "irrelevant";

export type Recommendation = {
  id: string;
  opportunity_id: string;
  action_code: RecommendationActionCode;
  status: "proposed" | "accepted" | "dismissed" | "completed";
  rationale: Record<string, unknown>;
  feedback_count: number;
  created_at: string;
  updated_at: string;
};

export async function listRecommendations(
  client: PoolClient,
  principal: AuthPrincipal,
  opportunityId: string | null = null,
  limit = 50
): Promise<Recommendation[]> {
  const safeLimit = Math.min(Math.max(limit, 1), 100);
  const result = await client.query<Recommendation>(
    "select * from growth.list_recommendations($1, $2, $3)",
    [principal.workspaceId, opportunityId, safeLimit]
  );
  return result.rows;
}

export async function createRecommendation(
  client: PoolClient,
  principal: AuthPrincipal,
  opportunityId: string,
  actionCode: RecommendationActionCode
): Promise<Recommendation> {
  const result = await client.query<Recommendation>(
    "select * from growth.create_recommendation($1, $2, $3)",
    [principal.workspaceId, opportunityId, actionCode]
  );
  const recommendation = result.rows[0];
  if (!recommendation) throw new Error("recommendation creation returned no row");
  return recommendation;
}

export async function recordRecommendationFeedback(
  client: PoolClient,
  principal: AuthPrincipal,
  recommendationId: string,
  feedback: RecommendationFeedback,
  note: string | null
) {
  const result = await client.query<{
    id: string;
    recommendation_id: string;
    feedback: RecommendationFeedback;
    note: string | null;
    created_at: string;
    recommendation_status: Recommendation["status"];
  }>(
    "select * from growth.record_recommendation_feedback($1, $2, $3, $4)",
    [principal.workspaceId, recommendationId, feedback, note]
  );
  return result.rows[0];
}
