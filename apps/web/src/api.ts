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
  options: { method?: string; body?: unknown; useDevelopmentIdentity?: boolean } = {}
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

export async function signUp(email: string, password: string): Promise<IdentitySignupResponse> {
  csrfToken = null;
  return requestJson<IdentitySignupResponse>("/v1/auth/signup", {
    method: "POST",
    body: { email, password },
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

export async function authorizeInstagram(managedAccountId: string): Promise<InstagramAuthorizeResponse> {
  return requestJson<InstagramAuthorizeResponse>("/v1/integrations/instagram/authorize", {
    method: "POST",
    body: { managedAccountId }
  });
}

export async function reconnectInstagram(managedAccountId: string): Promise<InstagramAuthorizeResponse> {
  return requestJson<InstagramAuthorizeResponse>("/v1/integrations/instagram/reconnect", {
    method: "POST",
    body: { managedAccountId }
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
