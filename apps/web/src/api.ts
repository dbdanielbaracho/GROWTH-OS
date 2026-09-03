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

export type RelatedInsight = {
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
  evidence: InsightEvidence[];
};

export type OpportunityDetail = {
  status: "ok";
  opportunity: OpportunitySummary;
  evidence: OpportunityEvidence[];
  related_insights: RelatedInsight[];
};

type OpportunityListResponse = {
  status: "ok";
  opportunities: OpportunitySummary[];
};

export class RadarApiError extends Error {
  constructor(
    public readonly httpStatus: number,
    public readonly apiStatus: string
  ) {
    super(`Opportunity Radar request failed: ${httpStatus} ${apiStatus}`);
  }
}

const apiBase = String(import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "");

function developmentIdentityHeaders(): Record<string, string> {
  if (!import.meta.env.DEV) return {};

  const userId = String(import.meta.env.VITE_DEV_USER_ID ?? "");
  const workspaceId = String(import.meta.env.VITE_DEV_WORKSPACE_ID ?? "");
  if (!userId || !workspaceId) return {};

  return {
    "x-user-id": userId,
    "x-workspace-id": workspaceId
  };
}

async function requestJson<T>(path: string): Promise<T> {
  const response = await fetch(`${apiBase}${path}`, {
    headers: {
      accept: "application/json",
      ...developmentIdentityHeaders()
    },
    credentials: "include"
  });

  if (!response.ok) {
    let apiStatus = "request_failed";
    try {
      const body = await response.json() as { status?: string };
      if (body.status) apiStatus = body.status;
    } catch {
      // Keep the generic status if the upstream body is not JSON.
    }
    throw new RadarApiError(response.status, apiStatus);
  }

  return response.json() as Promise<T>;
}

export async function fetchOpportunities(): Promise<OpportunitySummary[]> {
  const response = await requestJson<OpportunityListResponse>("/v1/opportunities");
  return response.opportunities;
}

export async function fetchOpportunityDetail(id: string): Promise<OpportunityDetail> {
  return requestJson<OpportunityDetail>(`/v1/opportunities/${encodeURIComponent(id)}`);
}
