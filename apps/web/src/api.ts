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

export type WorkspaceSummary = {
  id: string;
  name: string;
  default_market: string;
  default_language: string;
  default_timezone: string;
  status: "active" | "suspended" | "deleting";
  role: "owner" | "admin" | "editor" | "viewer";
  can_publish: boolean;
  membership_status: "active" | "invited" | "revoked";
};

export type AuthSessionResponse = {
  status: "ok";
  session: {
    user_id: string;
    amr: string[];
    absolute_expires_at: string;
    idle_expires_at: string;
  };
  workspaces: WorkspaceSummary[];
  selected_workspace: WorkspaceSummary | null;
  csrf_token: string;
};

export type YoutubeIntegration = {
  managed_account_id: string;
  owner_type: string;
  authority_status: string;
  contribution_eligibility: string;
  connection_id: string | null;
  connection_state: string | null;
  connection_updated_at: string | null;
  social_account_id: string | null;
  provider_account_id: string | null;
  handle: string | null;
  account_type: string | null;
  market: string | null;
  source_timezone: string | null;
};

export type YoutubeStatusResponse = {
  status: "ok";
  configured: boolean;
  derived_analytics_policy_accepted: boolean;
  integrations: YoutubeIntegration[];
};

export type YoutubeAuthorizeResponse = {
  status: "ok";
  connectionId: string;
  authorizationUrl: string;
};

export type YoutubeSyncResponse = {
  status: "ok";
  connectionId: string;
  requestNonce: string;
  socialAccountId: string;
  requestedStartDate: string;
  requestedEndDate: string;
  returnedThroughDate: string | null;
  observationsProcessed: number;
  rowsReceived: number;
  derivedAnalyticsPolicyAccepted: boolean;
  intelligenceStatus: "opportunity_created" | "insufficient_signal";
  signalId: string | null;
  insightId: string | null;
  opportunityId: string | null;
  intelligenceObservationsUsed: number;
  intelligenceDeltaRatio: number | null;
};


export type InstagramIntegration = {
  managed_account_id: string;
  owner_type: string;
  authority_status: string;
  contribution_eligibility: string;
  connection_id: string | null;
  connection_state: string | null;
  connection_updated_at: string | null;
  social_account_id: string | null;
  provider_account_id: string | null;
  handle: string | null;
  account_type: string | null;
  market: string | null;
  source_timezone: string | null;
};

export type InstagramStatusResponse = {
  status: "ok";
  configured: boolean;
  integrations: InstagramIntegration[];
};

export type InstagramAuthorizeResponse = {
  status: "ok";
  connectionId: string;
  authorizationUrl: string;
};

export type InstagramRefreshResponse = {
  status: "ok";
  connectionId: string;
  tokenExpiresAt: string;
};

export type InstagramSyncResponse = {
  status: "ok";
  connectionId: string;
  requestNonce: string;
  collectionRunId: string;
  socialAccountId: string;
  requestedLookbackDays: number;
  rowsReceived: number;
  mediaProcessed: number;
  observationsProcessed: number;
  oldestMediaAt: string | null;
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
    super(`Growth OS request failed: ${httpStatus} ${apiStatus}`);
  }
}

// Production is deliberately same-origin: the Fastify production process
// serves both the built web app and /v1/* API. A production VITE_API_BASE_URL
// value cannot move authentication requests to a second origin.
const apiBase = import.meta.env.PROD
  ? ""
  : String(import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "");
let csrfToken: string | null = null;

export function hasDevelopmentIdentity(): boolean {
  if (!import.meta.env.DEV) return false;
  return Boolean(import.meta.env.VITE_DEV_USER_ID && import.meta.env.VITE_DEV_WORKSPACE_ID);
}

function developmentIdentityHeaders(): Record<string, string> {
  if (!hasDevelopmentIdentity()) return {};

  return {
    "x-user-id": String(import.meta.env.VITE_DEV_USER_ID),
    "x-workspace-id": String(import.meta.env.VITE_DEV_WORKSPACE_ID)
  };
}

function unsafeMethod(method: string): boolean {
  return !["GET", "HEAD", "OPTIONS"].includes(method.toUpperCase());
}

async function responseError(response: Response): Promise<never> {
  let apiStatus = "request_failed";
  try {
    const body = await response.json() as { status?: string };
    if (body.status) apiStatus = body.status;
  } catch {
    // Keep the generic status if the upstream body is not JSON.
  }

  if (response.status === 401) csrfToken = null;
  throw new RadarApiError(response.status, apiStatus);
}

async function requestJson<T>(
  path: string,
  options: { method?: string; body?: unknown; useDevelopmentIdentity?: boolean; signal?: AbortSignal } = {}
): Promise<T> {
  const method = (options.method ?? "GET").toUpperCase();
  const headers: Record<string, string> = {
    accept: "application/json",
    ...(options.useDevelopmentIdentity === false ? {} : developmentIdentityHeaders())
  };

  if (options.body !== undefined) headers["content-type"] = "application/json";
  if (unsafeMethod(method) && csrfToken) headers["x-csrf-token"] = csrfToken;

  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers,
    credentials: "include",
    ...(options.signal ? { signal: options.signal } : {}),
    ...(options.body !== undefined ? { body: JSON.stringify(options.body) } : {})
  });

  if (!response.ok) return responseError(response);
  return response.json() as Promise<T>;
}

async function requestNoContent(
  path: string,
  options: { method: string; body?: unknown }
): Promise<void> {
  const method = options.method.toUpperCase();
  const headers: Record<string, string> = { accept: "application/json" };
  if (options.body !== undefined) headers["content-type"] = "application/json";
  if (unsafeMethod(method) && csrfToken) headers["x-csrf-token"] = csrfToken;

  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers,
    credentials: "include",
    ...(options.body !== undefined ? { body: JSON.stringify(options.body) } : {})
  });

  if (!response.ok) return responseError(response);
}

function captureSession(response: AuthSessionResponse): AuthSessionResponse {
  csrfToken = response.csrf_token;
  return response;
}

export async function fetchAuthSession(): Promise<AuthSessionResponse> {
  return captureSession(await requestJson<AuthSessionResponse>("/v1/auth/session", {
    useDevelopmentIdentity: false
  }));
}

export type IdentitySignupResponse = {
  status: "verification_required";
};

export type WorkspaceCreateResponse = {
  status: "created";
  workspace_id: string;
};

export type ContentCreateResponse = {
  status: "created";
  item: {
    id: string;
    workspace_id: string;
    objective: string | null;
    market: string;
    language: string;
    platform_target: string | null;
    source_type: string;
    status: string;
    created_by: string;
    created_at: string;
  };
  version: {
    id: string;
    workspace_id: string;
    content_item_id: string;
    version_no: number;
    body: string;
    structure_json: Record<string, unknown>;
    ai_provenance: Record<string, unknown> | null;
    checksum: string;
    created_at: string;
  };
};

export async function signUp(email: string, password: string): Promise<IdentitySignupResponse> {
  csrfToken = null;
  return requestJson<IdentitySignupResponse>("/v1/auth/signup", {
    method: "POST",
    body: { email, password },
    useDevelopmentIdentity: false
  });
}

export async function requestPasswordReset(email: string): Promise<{ status: "password_reset_if_account_exists" }> {
  csrfToken = null;
  return requestJson<{ status: "password_reset_if_account_exists" }>("/v1/auth/password-reset/request", {
    method: "POST",
    body: { email },
    useDevelopmentIdentity: false
  });
}

export async function completePasswordReset(token: string, password: string): Promise<{ status: "password_reset_completed"; user_id?: string }> {
  csrfToken = null;
  return requestJson<{ status: "password_reset_completed"; user_id?: string }>("/v1/auth/password-reset/complete", {
    method: "POST",
    body: { token, password },
    useDevelopmentIdentity: false
  });
}

export async function verifyEmail(token: string): Promise<{ status: "verified"; user_id?: string }> {
  csrfToken = null;
  return requestJson<{ status: "verified"; user_id?: string }>("/v1/auth/verify-email", {
    method: "POST",
    body: { token },
    useDevelopmentIdentity: false
  });
}

export async function createWorkspace(input: {
  name: string;
  defaultMarket: string;
  defaultLanguage: string;
  defaultTimezone: string;
}): Promise<WorkspaceCreateResponse> {
  return requestJson<WorkspaceCreateResponse>("/v1/workspaces", {
    method: "POST",
    body: input,
    useDevelopmentIdentity: false
  });
}


export type ContentListItem = {
  id: string;
  objective: string | null;
  market: string;
  language: string;
  platform_target: string | null;
  source_type: string;
  status: string;
  created_by: string | null;
  created_at: string;
  current_version_id: string | null;
  version_no: number | null;
  body: string | null;
  structure_json: Record<string, unknown> | null;
  ai_provenance: Record<string, unknown> | null;
  checksum: string | null;
  version_created_at: string | null;
};

type ContentListResponse = {
  status: "ok";
  content: ContentListItem[];
};

export type ContentDecisionResponse = {
  status: "ok";
  item: ContentCreateResponse["item"];
  approval: Record<string, unknown>;
};

export async function createContent(input: {
  objective?: string;
  market: string;
  language: string;
  platformTarget?: string;
  sourceType: string;
  body: string;
  structure?: Record<string, unknown>;
  aiProvenance?: Record<string, unknown>;
}): Promise<ContentCreateResponse> {
  return requestJson<ContentCreateResponse>("/v1/content", {
    method: "POST",
    body: input
  });
}

export async function fetchContent(): Promise<ContentListItem[]> {
  const response = await requestJson<ContentListResponse>("/v1/content");
  return response.content;
}

export async function appendContentVersion(input: {
  contentItemId: string;
  body: string;
  structure?: Record<string, unknown>;
  aiProvenance?: Record<string, unknown>;
}): Promise<ContentCreateResponse> {
  return requestJson<ContentCreateResponse>(`/v1/content/${encodeURIComponent(input.contentItemId)}/versions`, {
    method: "POST",
    body: {
      body: input.body,
      structure: input.structure,
      aiProvenance: input.aiProvenance
    }
  });
}

export async function approveContentVersion(
  contentVersionId: string,
  notes?: string
): Promise<ContentDecisionResponse> {
  return requestJson<ContentDecisionResponse>(
    `/v1/content/versions/${encodeURIComponent(contentVersionId)}/approve`,
    { method: "POST", body: { notes } }
  );
}

export async function requestContentChanges(
  contentVersionId: string,
  notes?: string
): Promise<ContentDecisionResponse> {
  return requestJson<ContentDecisionResponse>(
    `/v1/content/versions/${encodeURIComponent(contentVersionId)}/request-changes`,
    { method: "POST", body: { notes } }
  );
}

export async function signIn(email: string, password: string): Promise<AuthSessionResponse> {
  csrfToken = null;
  return captureSession(await requestJson<AuthSessionResponse>("/v1/auth/signin", {
    method: "POST",
    body: { email, password },
    useDevelopmentIdentity: false
  }));
}

export async function selectWorkspace(workspaceId: string): Promise<AuthSessionResponse> {
  return captureSession(await requestJson<AuthSessionResponse>("/v1/auth/workspace", {
    method: "POST",
    body: { workspaceId },
    useDevelopmentIdentity: false
  }));
}

export async function signOut(): Promise<void> {
  await requestNoContent("/v1/auth/signout", { method: "POST" });
  csrfToken = null;
}

export async function fetchOpportunities(): Promise<OpportunitySummary[]> {
  const response = await requestJson<OpportunityListResponse>("/v1/opportunities");
  return response.opportunities;
}

export async function fetchOpportunityDetail(id: string): Promise<OpportunityDetail> {
  return requestJson<OpportunityDetail>(`/v1/opportunities/${encodeURIComponent(id)}`);
}

export async function fetchYoutubeStatus(): Promise<YoutubeStatusResponse> {
  return requestJson<YoutubeStatusResponse>("/v1/integrations/youtube/status");
}

export async function authorizeYoutube(managedAccountId: string): Promise<YoutubeAuthorizeResponse> {
  return requestJson<YoutubeAuthorizeResponse>("/v1/integrations/youtube/authorize", {
    method: "POST",
    body: { managedAccountId }
  });
}

export async function syncYoutube(
  connectionId: string,
  requestNonce: string,
  lookbackDays = 7
): Promise<YoutubeSyncResponse> {
  return requestJson<YoutubeSyncResponse>("/v1/integrations/youtube/sync", {
    method: "POST",
    body: { connectionId, requestNonce, lookbackDays }
  });
}

export async function fetchInstagramStatus(): Promise<InstagramStatusResponse> {
  return requestJson<InstagramStatusResponse>("/v1/integrations/instagram/status");
}

export async function authorizeInstagram(managedAccountId: string, signal?: AbortSignal): Promise<InstagramAuthorizeResponse> {
  return requestJson<InstagramAuthorizeResponse>("/v1/integrations/instagram/authorize", {
    method: "POST",
    body: { managedAccountId },
    signal
  });
}

export async function reconnectInstagram(managedAccountId: string, signal?: AbortSignal): Promise<InstagramAuthorizeResponse> {
  return requestJson<InstagramAuthorizeResponse>("/v1/integrations/instagram/reconnect", {
    method: "POST",
    body: { managedAccountId },
    signal
  });
}

export async function syncInstagram(
  connectionId: string,
  requestNonce: string,
  lookbackDays = 7
): Promise<InstagramSyncResponse> {
  return requestJson<InstagramSyncResponse>("/v1/integrations/instagram/sync", {
    method: "POST",
    body: { connectionId, requestNonce, lookbackDays }
  });
}

export async function refreshInstagram(connectionId: string): Promise<InstagramRefreshResponse> {
  return requestJson<InstagramRefreshResponse>(
    `/v1/integrations/instagram/${encodeURIComponent(connectionId)}/refresh`,
    { method: "POST" }
  );
}

export async function revokeInstagram(connectionId: string): Promise<void> {
  await requestNoContent(
    `/v1/integrations/instagram/${encodeURIComponent(connectionId)}/revoke`,
    { method: "POST" }
  );
}


export type PublicationIntentListItem = {
  id: string;
  social_account_id: string;
  content_version_id: string;
  status: "ready" | "scheduled" | "queued" | "sending" | "failed_retryable" | "retrying" | "needs_user_action" | "confirmed" | "cancelled" | "superseded";
  scheduled_for: string | null;
  current_attempt_no: number | null;
  retry_count: number;
  last_error_class: string | null;
  provider_content_id: string | null;
  provider_permalink: string | null;
  created_at: string;
  updated_at: string;
  cancelled_at: string | null;
};

type PublicationIntentListResponse = {
  status: "ok";
  publicationIntents: PublicationIntentListItem[];
};

export async function fetchPublicationIntents(): Promise<PublicationIntentListItem[]> {
  const response = await requestJson<PublicationIntentListResponse>("/v1/publication-intents");
  return response.publicationIntents;
}


export type PublicationIntentMutationResponse = {
  status: "created" | "processed" | "cancelled";
  publicationIntent: PublicationIntentListItem;
};

export async function createPublicationIntent(input: {
  socialAccountId: string;
  contentVersionId: string;
  requestNonce: string;
  idempotencyKey: string;
}): Promise<PublicationIntentMutationResponse> {
  return requestJson<PublicationIntentMutationResponse>("/v1/publication-intents", {
    method: "POST",
    body: input
  });
}

export async function executePublicationIntent(
  publicationIntentId: string
): Promise<PublicationIntentMutationResponse> {
  return requestJson<PublicationIntentMutationResponse>(
    `/v1/publication-intents/${encodeURIComponent(publicationIntentId)}/execute`,
    { method: "POST" }
  );
}

export async function cancelPublicationIntent(
  publicationIntentId: string
): Promise<PublicationIntentMutationResponse> {
  return requestJson<PublicationIntentMutationResponse>(
    `/v1/publication-intents/${encodeURIComponent(publicationIntentId)}/cancel`,
    { method: "POST" }
  );
}


export type MetricAnalyticsSummary = {
  social_account_id: string;
  platform: string;
  provider_account_id: string;
  handle: string | null;
  metric_name: string;
  observation_count: number;
  total_value: number;
  latest_observed_at: string;
  latest_effective_at: string;
  complete_observations: number;
  fresh_observations: number;
};

export type MetricAnalyticsResponse = {
  status: "ok";
  from: string;
  to: string;
  metrics: MetricAnalyticsSummary[];
};

async function fetchMetricAnalyticsResponse(
  from?: string,
  to?: string
): Promise<MetricAnalyticsResponse> {
  const params = new URLSearchParams();
  if (from) params.set("from", from);
  if (to) params.set("to", to);
  return requestJson<MetricAnalyticsResponse>(
    `/v1/analytics/metrics${params.size > 0 ? `?${params.toString()}` : ""}`
  );
}

export async function fetchMetricAnalyticsSummary(
  from?: string,
  to?: string
): Promise<MetricAnalyticsSummary[]> {
  return (await fetchMetricAnalyticsResponse(from, to)).metrics;
}

export async function fetchMetricAnalyticsSnapshot(
  from?: string,
  to?: string
): Promise<MetricAnalyticsResponse> {
  return fetchMetricAnalyticsResponse(from, to);
}


export type MetricQualityAnomaly = {
  social_account_id: string;
  platform: string;
  provider_account_id: string;
  handle: string | null;
  metric_name: string;
  observation_count: number;
  latest_observed_at: string;
  latest_effective_at: string;
  complete_observations: number;
  fresh_observations: number;
  quality_status: "incomplete" | "stale";
  anomaly_reason: "incomplete_observations" | "stale_observations";
  completeness_ratio: number;
  freshness_ratio: number;
};

export type MetricQualityAnomalyResponse = {
  status: "ok";
  from: string;
  to: string;
  anomalies: MetricQualityAnomaly[];
};

export async function fetchMetricQualityAnomalies(
  from?: string,
  to?: string
): Promise<MetricQualityAnomaly[]> {
  const params = new URLSearchParams();
  if (from) params.set("from", from);
  if (to) params.set("to", to);
  const response = await requestJson<MetricQualityAnomalyResponse>(
    `/v1/analytics/anomalies${params.size > 0 ? `?${params.toString()}` : ""}`
  );
  return response.anomalies;
}


export type Recommendation = {
  id: string;
  opportunity_id: string;
  action_code: "draft_content" | "review_evidence" | "plan_experiment";
  status: "proposed" | "accepted" | "dismissed" | "completed";
  rationale: Record<string, unknown>;
  feedback_count: number;
  created_at: string;
  updated_at: string;
};

type RecommendationListResponse = {
  status: "ok";
  recommendations: Recommendation[];
};

export async function fetchRecommendations(opportunityId?: string): Promise<Recommendation[]> {
  const query = opportunityId ? `?opportunity_id=${encodeURIComponent(opportunityId)}` : "";
  const response = await requestJson<RecommendationListResponse>(`/v1/recommendations${query}`);
  return response.recommendations;
}

export async function createRecommendation(
  opportunityId: string,
  actionCode: Recommendation["action_code"]
): Promise<Recommendation> {
  const response = await requestJson<{ status: "created"; recommendation: Recommendation }>(
    `/v1/opportunities/${encodeURIComponent(opportunityId)}/recommendations`,
    { method: "POST", body: { action_code: actionCode } }
  );
  return response.recommendation;
}

export async function recordRecommendationFeedback(
  recommendationId: string,
  feedback: "accepted" | "dismissed" | "completed" | "irrelevant",
  note?: string
): Promise<{ status: "recorded"; feedback: { recommendation_status: Recommendation["status"] } }> {
  return requestJson<{ status: "recorded"; feedback: { recommendation_status: Recommendation["status"] } }>(
    `/v1/recommendations/${encodeURIComponent(recommendationId)}/feedback`,
    { method: "POST", body: { feedback, note } }
  );
}


export type Experiment = {
  id: string;
  opportunity_id: string | null;
  name: string;
  hypothesis: string;
  decision_rule: string;
  status: "draft" | "running" | "completed" | "archived";
  variant_count: number;
  created_at: string;
  updated_at: string;
};

export type ExperimentVariant = {
  id: string;
  experiment_id: string;
  label: string;
  lineage: Record<string, unknown>;
  status: "candidate" | "active" | "winner" | "loser" | "archived";
  created_at: string;
};

export async function createExperiment(input: {
  opportunityId: string;
  name: string;
  hypothesis: string;
  decisionRule: string;
}): Promise<Experiment> {
  const response = await requestJson<{ status: "created"; experiment: Experiment }>("/v1/experiments", {
    method: "POST",
    body: {
      opportunity_id: input.opportunityId,
      name: input.name,
      hypothesis: input.hypothesis,
      decision_rule: input.decisionRule
    }
  });
  return response.experiment;
}

export async function addExperimentVariant(
  experimentId: string,
  label: string,
  opportunityId: string
): Promise<ExperimentVariant> {
  const response = await requestJson<{ status: "created"; variant: ExperimentVariant }>(
    `/v1/experiments/${encodeURIComponent(experimentId)}/variants`,
    {
      method: "POST",
      body: { label, lineage: { source_opportunity_id: opportunityId, autonomous_publishing: false } }
    }
  );
  return response.variant;
}


export type AutomationPolicy = {
  id: string | null;
  workspace_id: string;
  mode: "approval_required" | "disabled";
  daily_request_limit: number;
  kill_switch: boolean;
  created_at: string;
  updated_at: string;
};

export type AutomationActionRequest = {
  id: string;
  policy_id: string;
  action_code: "draft_content" | "review_evidence" | "plan_experiment" | "publish_content" | "multiply_variant";
  target_ref: string;
  evidence_ref: string | null;
  status: "pending" | "approved" | "rejected" | "cancelled";
  requested_by: string;
  approved_by: string | null;
  note: string | null;
  created_at: string;
  decided_at: string | null;
};

export async function fetchAutomationPolicy(): Promise<AutomationPolicy> {
  const response = await requestJson<{ status: "ok"; policy: AutomationPolicy }>("/v1/automation/policy");
  return response.policy;
}

export async function updateAutomationPolicy(input: {
  mode: AutomationPolicy["mode"];
  dailyRequestLimit: number;
  killSwitch: boolean;
}): Promise<AutomationPolicy> {
  const response = await requestJson<{ status: "updated"; policy: AutomationPolicy }>("/v1/automation/policy", {
    method: "PUT",
    body: {
      mode: input.mode,
      daily_request_limit: input.dailyRequestLimit,
      kill_switch: input.killSwitch
    }
  });
  return response.policy;
}

export async function fetchAutomationRequests(): Promise<AutomationActionRequest[]> {
  const response = await requestJson<{ status: "ok"; requests: AutomationActionRequest[] }>("/v1/automation/requests");
  return response.requests;
}

export async function createAutomationRequest(input: {
  actionCode: AutomationActionRequest["action_code"];
  targetRef: string;
  evidenceRef: string;
  note?: string;
}): Promise<AutomationActionRequest> {
  const response = await requestJson<{ status: "created"; request: AutomationActionRequest }>("/v1/automation/requests", {
    method: "POST",
    body: {
      action_code: input.actionCode,
      target_ref: input.targetRef,
      evidence_ref: input.evidenceRef,
      note: input.note
    }
  });
  return response.request;
}

export async function decideAutomationRequest(
  requestId: string,
  decision: "approve" | "reject" | "cancel",
  note?: string
): Promise<AutomationActionRequest> {
  const response = await requestJson<{ status: "decided"; request: AutomationActionRequest }>(
    "/v1/automation/requests/" + encodeURIComponent(requestId) + "/decision",
    { method: "POST", body: { decision, note } }
  );
  return response.request;
}
