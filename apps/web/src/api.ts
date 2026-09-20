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

export type WorkspaceMember = {
  user_id: string;
  role: "owner" | "admin" | "editor" | "viewer";
  can_publish: boolean;
  status: "active" | "invited" | "revoked";
  created_at: string;
};

export type WorkspaceInvitationRole = "admin" | "editor" | "viewer";

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

export type InstagramMediaRecord = {
  media_id: string;
  provider_media_id: string;
  media_type: string;
  media_product_type: string | null;
  permalink: string | null;
  caption: string | null;
  posted_at: string | null;
  media_url: string | null;
  thumbnail_url: string | null;
  first_seen_at: string;
  last_synced_at: string;
  latest_like_count: string | null;
  latest_comments_count: string | null;
  latest_metric_count: number;
  observation_count: string;
  first_observed_at: string | null;
  last_observed_at: string | null;
  metric_history: Array<{
    metric_name: string;
    value: string | number | null;
    observed_at: string;
  }>;
  opportunity_count: string;
};

export type InstagramMediaResponse = {
  status: "ok";
  connectionId: string;
  lookbackDays: number;
  media: InstagramMediaRecord[];
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
  options: {
    method?: string;
    body?: unknown;
    useDevelopmentIdentity?: boolean;
    signal?: AbortSignal;
    retryOnCsrf?: boolean;
  } = {}
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

  // A session refresh can race an integration action and leave the in-memory
  // CSRF token stale or empty. Refresh it once, then retry the same request.
  // The retry is bounded and does not weaken the server-side CSRF check.
  if (
    response.status === 403
    && unsafeMethod(method)
    && options.retryOnCsrf !== false
  ) {
    try {
      const session = await requestJson<AuthSessionResponse>("/v1/auth/session", {
        useDevelopmentIdentity: false,
        retryOnCsrf: false
      });
      captureSession(session);
      return requestJson<T>(path, { ...options, retryOnCsrf: false });
    } catch {
      // Preserve the original API error if the session cannot be refreshed.
    }
  }

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

export async function fetchWorkspaceMembers(workspaceId: string): Promise<WorkspaceMember[]> {
  const response = await requestJson<{ status: "ok"; members: WorkspaceMember[] }>(
    `/v1/workspaces/${encodeURIComponent(workspaceId)}/members`,
    { useDevelopmentIdentity: false }
  );
  return response.members;
}

export async function inviteWorkspaceMember(input: {
  workspaceId: string;
  email: string;
  role: WorkspaceInvitationRole;
  canPublish: boolean;
}): Promise<void> {
  await requestJson<{ status: "invitation_sent" }>(
    `/v1/workspaces/${encodeURIComponent(input.workspaceId)}/invitations`,
    {
      method: "POST",
      body: { email: input.email, role: input.role, canPublish: input.canPublish },
      useDevelopmentIdentity: false
    }
  );
}

export async function updateWorkspaceMember(input: {
  workspaceId: string;
  userId: string;
  role: WorkspaceInvitationRole;
  canPublish: boolean;
  status: "active" | "revoked";
}): Promise<WorkspaceMember> {
  const response = await requestJson<{ status: "ok"; member: WorkspaceMember }>(
    `/v1/workspaces/${encodeURIComponent(input.workspaceId)}/members/${encodeURIComponent(input.userId)}`,
    {
      method: "PATCH",
      body: { role: input.role, canPublish: input.canPublish, status: input.status },
      useDevelopmentIdentity: false
    }
  );
  return response.member;
}

export async function acceptWorkspaceInvitation(token: string): Promise<string> {
  const response = await requestJson<{ status: "accepted"; workspace_id: string }>(
    "/v1/auth/invitations/accept",
    {
      method: "POST",
      body: { token },
      useDevelopmentIdentity: false
    }
  );
  return response.workspace_id;
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

export type ContentReviewSubmissionResponse = {
  status: "ok";
  item: ContentCreateResponse["item"];
  submission: {
    id: string;
    workspace_id: string;
    content_version_id: string;
    actor_user_id: string;
    note: string | null;
    submitted_at: string;
  };
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

export async function submitContentForReview(
  contentVersionId: string,
  note?: string
): Promise<ContentReviewSubmissionResponse> {
  return requestJson<ContentReviewSubmissionResponse>(
    `/v1/content/versions/${encodeURIComponent(contentVersionId)}/submit-review`,
    { method: "POST", body: { note } }
  );
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

export async function fetchInstagramMedia(
  connectionId: string,
  lookbackDays = 7,
  limit = 50
): Promise<InstagramMediaRecord[]> {
  const params = new URLSearchParams({
    lookback_days: String(lookbackDays),
    limit: String(limit)
  });
  const response = await requestJson<InstagramMediaResponse>(
    `/v1/integrations/instagram/${encodeURIComponent(connectionId)}/media?${params.toString()}`
  );
  return response.media;
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
  mediaAssetId?: string;
  scheduledFor?: string;
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

export type PublicationReconciliationInput = {
  attemptNo: number;
  method: "exact" | "resumable_status" | "fuzzy_recent_content" | "manual";
  confidence: "exact" | "high" | "medium" | "low" | "none";
  reconciliationStatus: "pending" | "matched" | "not_found" | "ambiguous" | "escalated";
  candidateProviderContentId?: string;
  evidenceRef?: string;
};

export async function reconcilePublicationIntent(
  publicationIntentId: string,
  input: PublicationReconciliationInput
): Promise<void> {
  await requestJson<{ status: "reconciled"; reconciliation: unknown }>(
    `/v1/publication-intents/${encodeURIComponent(publicationIntentId)}/reconcile`,
    { method: "POST", body: input }
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


export type RecommendationLearningContext = {
  rule_version: "opportunity.learning.v1";
  completed_experiment_count: number;
  winner_count: number;
  recommendation_feedback: {
    accepted: number;
    completed: number;
    dismissed: number;
    irrelevant: number;
  };
  latest_winner: null | {
    experiment_id: string;
    variant_id: string;
    label: string;
    evidence_ref: string;
    recorded_at: string;
  };
};

export type Recommendation = {
  id: string;
  opportunity_id: string;
  action_code: "draft_content" | "review_evidence" | "plan_experiment";
  status: "proposed" | "accepted" | "dismissed" | "completed";
  rationale: Record<string, unknown> & { learning?: RecommendationLearningContext };
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
  latest_outcome?: "winner" | "loser" | "inconclusive" | null;
  latest_evidence_ref?: string | null;
  feedback_created_at?: string | null;
};

export async function fetchExperiments(opportunityId?: string): Promise<Experiment[]> {
  const response = await requestJson<{ status: "ok"; experiments: Experiment[] }>("/v1/experiments");
  return opportunityId
    ? response.experiments.filter((experiment) => experiment.opportunity_id === opportunityId)
    : response.experiments;
}

export async function fetchExperimentVariants(experimentId: string): Promise<ExperimentVariant[]> {
  const response = await requestJson<{ status: "ok"; variants: ExperimentVariant[] }>(
    `/v1/experiments/${encodeURIComponent(experimentId)}/variants`
  );
  return response.variants;
}

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
  return { ...response.experiment, variant_count: response.experiment.variant_count ?? 0 };
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
  return { ...response.variant, latest_outcome: null, latest_evidence_ref: null, feedback_created_at: null };
}

export async function recordExperimentFeedback(input: {
  experimentId: string;
  variantId: string;
  outcome: "winner" | "loser" | "inconclusive";
  evidenceRef: string;
  note?: string;
}): Promise<void> {
  await requestJson<{ status: "recorded"; feedback: unknown }>(
    `/v1/experiments/${encodeURIComponent(input.experimentId)}/feedback`,
    {
      method: "POST",
      body: {
        variant_id: input.variantId,
        outcome: input.outcome,
        evidence_ref: input.evidenceRef,
        note: input.note
      }
    }
  );
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
  workspace_id: string;
  policy_id: string;
  action_code: "draft_content" | "review_evidence" | "plan_experiment" | "publish_content" | "multiply_variant";
  target_ref: string;
  evidence_ref: string | null;
  status: "pending" | "approved" | "rejected" | "cancelled";
  requested_by: string;
  approved_by: string | null;
  note: string | null;
  action_payload: Record<string, unknown>;
  execution_status: "not_ready" | "ready" | "executing" | "succeeded" | "needs_input" | "failed";
  execution_result_ref: string | null;
  execution_error_class: string | null;
  execution_started_at: string | null;
  executed_at: string | null;
  execution_attempts: number;
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
  actionPayload?: Record<string, unknown>;
  note?: string;
}): Promise<AutomationActionRequest> {
  const response = await requestJson<{ status: "created"; request: AutomationActionRequest }>("/v1/automation/requests", {
    method: "POST",
    body: {
      action_code: input.actionCode,
      target_ref: input.targetRef,
      evidence_ref: input.evidenceRef,
      action_payload: input.actionPayload ?? {},
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


export async function executeAutomationRequest(
  requestId: string
): Promise<AutomationActionRequest> {
  const response = await requestJson<{ status: "processed"; request: AutomationActionRequest }>(
    "/v1/automation/requests/" + encodeURIComponent(requestId) + "/execute",
    { method: "POST" }
  );
  return response.request;
}


export type WorkspaceEntitlements = {
  plan_code: "free" | "pro" | "enterprise";
  plan_name: string;
  subscription_status: "trialing" | "active" | "past_due" | "cancelled";
  monthly_action_limit: number;
  used_automation_requests: number;
  period_start: string;
  period_end: string;
};

export type EnterprisePolicy = {
  id: string | null;
  workspace_id: string;
  data_retention_days: number;
  support_tier: "standard" | "priority" | "dedicated";
  legal_acceptance_ref: string | null;
  deletion_requested_at: string | null;
  created_at: string;
  updated_at: string;
};

export async function fetchWorkspaceEntitlements(): Promise<WorkspaceEntitlements> {
  const response = await requestJson<{ status: "ok"; entitlements: WorkspaceEntitlements }>("/v1/commercial/entitlements");
  return response.entitlements;
}

export async function fetchEnterprisePolicy(): Promise<EnterprisePolicy> {
  const response = await requestJson<{ status: "ok"; policy: EnterprisePolicy }>("/v1/commercial/enterprise-policy");
  return response.policy;
}

export async function updateEnterprisePolicy(input: {
  dataRetentionDays: number;
  supportTier: EnterprisePolicy["support_tier"];
  legalAcceptanceRef?: string;
}): Promise<EnterprisePolicy> {
  const response = await requestJson<{ status: "updated"; policy: EnterprisePolicy }>("/v1/commercial/enterprise-policy", {
    method: "PUT",
    body: {
      data_retention_days: input.dataRetentionDays,
      support_tier: input.supportTier,
      legal_acceptance_ref: input.legalAcceptanceRef
    }
  });
  return response.policy;
}


export type CopilotCitation = {
  kind: "opportunity" | "insight" | "evidence" | "metric" | "recommendation" | "experiment" | "automation";
  ref: string;
  label: string;
};

export type CopilotReply = {
  mode: "evidence_grounded";
  intent: "summary" | "metrics" | "evidence" | "actions" | "experiments" | "operations";
  answer: string;
  citations: CopilotCitation[];
  workspace_pulse: {
    opportunities: number;
    insights: number;
    metric_rows: number;
    quality_alerts: number;
    experiments: number;
    automation_needs_attention: number;
    automation_kill_switch: boolean;
  };
  suggested_prompts: string[];
  limitations: string[];
};

export async function queryCopilot(message: string): Promise<CopilotReply> {
  const response = await requestJson<{ status: "ok"; reply: CopilotReply }>("/v1/copilot/query", {
    method: "POST",
    body: { message }
  });
  return response.reply;
}


export type CreativeRequest = {
  id: string;
  workspace_id: string;
  content_item_id: string | null;
  content_version_id: string | null;
  source_type: "opportunity" | "insight" | "experiment" | "multiply" | "user_request" | "content";
  source_id: string;
  capability: string;
  modality: "text" | "image" | "video" | "audio" | "embedding";
  target_market: string;
  target_language: string;
  requested_by: string;
  status: "requested" | "in_progress" | "completed" | "failed" | "cancelled";
  created_at: string;
};

export type CreativeGeneration = {
  id: string;
  workspace_id: string;
  creative_request_id: string;
  provider: string;
  model: string | null;
  status: "requested" | "queued" | "processing" | "succeeded" | "failed" | "cancelled" | "ambiguous";
  supports_provider_idempotency: boolean;
  idempotency_key: string;
  external_handle: string | null;
  error_class: string | null;
  resolved_manually: boolean;
  resolved_by: string | null;
  resolved_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  created_at: string;
};

export type MediaAsset = {
  id: string;
  workspace_id: string;
  storage_ref: string;
  mime_type: string;
  checksum: string;
  rights_status: string;
  source_class: string;
  bytes: number | null;
  duration_seconds: number | null;
  width_px: number | null;
  height_px: number | null;
  purpose: "source" | "intermediate" | "publishable" | null;
  content_version_id: string | null;
  creative_generation_id: string | null;
  created_at: string;
};

export type MediaAssetLineage = {
  workspace_id: string;
  output_asset_id: string;
  input_asset_id: string;
  role: string | null;
  created_at: string;
};

export async function fetchCreativeRequests(): Promise<CreativeRequest[]> {
  const response = await requestJson<{ status: "ok"; creativeRequests: CreativeRequest[] }>("/v1/creative/requests");
  return response.creativeRequests;
}

export async function createCreativeRequest(input: {
  contentItemId?: string;
  contentVersionId?: string;
  sourceType: CreativeRequest["source_type"];
  sourceId: string;
  capability: string;
  modality: CreativeRequest["modality"];
  targetMarket: string;
  targetLanguage: string;
}): Promise<CreativeRequest> {
  const response = await requestJson<{ status: "created"; creativeRequest: CreativeRequest }>("/v1/creative/requests", { method: "POST", body: input });
  return response.creativeRequest;
}

export async function fetchCreativeGenerations(): Promise<CreativeGeneration[]> {
  const response = await requestJson<{ status: "ok"; creativeGenerations: CreativeGeneration[] }>("/v1/creative/generations");
  return response.creativeGenerations;
}

export async function createCreativeGeneration(input: {
  creativeRequestId: string;
  provider: string;
  model?: string;
  supportsProviderIdempotency?: boolean;
}): Promise<CreativeGeneration> {
  const response = await requestJson<{ status: "created"; creativeGeneration: CreativeGeneration }>("/v1/creative/generations", { method: "POST", body: input });
  return response.creativeGeneration;
}

export async function transitionCreativeGeneration(
  generationId: string,
  status: CreativeGeneration["status"]
): Promise<CreativeGeneration> {
  const response = await requestJson<{ status: "ok"; creativeGeneration: CreativeGeneration }>(
    `/v1/creative/generations/${encodeURIComponent(generationId)}`,
    { method: "PATCH", body: { status } }
  );
  return response.creativeGeneration;
}

export async function reconcileCreativeGeneration(
  generationId: string,
  resolvedStatus: "succeeded" | "failed"
): Promise<CreativeGeneration> {
  const response = await requestJson<{ status: "ok"; creativeGeneration: CreativeGeneration }>(
    `/v1/creative/generations/${encodeURIComponent(generationId)}/reconcile`,
    { method: "POST", body: { resolvedStatus } }
  );
  return response.creativeGeneration;
}

export async function fetchMediaAssets(): Promise<MediaAsset[]> {
  const response = await requestJson<{ status: "ok"; mediaAssets: MediaAsset[] }>("/v1/media-assets");
  return response.mediaAssets;
}

export async function createMediaAsset(input: {
  storageRef: string;
  mimeType: string;
  checksum: string;
  rightsStatus: string;
  sourceClass: string;
  bytes?: number;
  durationSeconds?: number;
  widthPx?: number;
  heightPx?: number;
  purpose?: MediaAsset["purpose"];
  contentVersionId?: string;
  creativeGenerationId?: string;
}): Promise<MediaAsset> {
  const response = await requestJson<{ status: "created"; mediaAsset: MediaAsset }>("/v1/media-assets", { method: "POST", body: input });
  return response.mediaAsset;
}

export async function fetchMediaAssetLineage(): Promise<MediaAssetLineage[]> {
  const response = await requestJson<{ status: "ok"; lineage: MediaAssetLineage[] }>("/v1/media-assets/lineage");
  return response.lineage;
}

export async function createMediaAssetLineage(input: {
  outputAssetId: string;
  inputAssetId: string;
  role?: string;
}): Promise<MediaAssetLineage> {
  const response = await requestJson<{ status: "created"; lineageEdge: MediaAssetLineage }>("/v1/media-assets/lineage", { method: "POST", body: input });
  return response.lineageEdge;
}


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
