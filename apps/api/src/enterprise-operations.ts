import type { PoolClient } from "pg";
import type { AuthPrincipal } from "./auth.js";

export type AgencyClient = {
  link_id: string;
  client_workspace_id: string;
  client_workspace_name: string;
  label: string;
  state: "active" | "paused";
  client_role: "owner" | "admin" | "editor" | "viewer";
  created_at: string;
  updated_at: string;
};

export type SupportCase = {
  id: string;
  workspace_id: string;
  category: "product" | "provider" | "privacy" | "security" | "billing";
  priority: "normal" | "high" | "urgent";
  state: "open" | "waiting_customer" | "resolved" | "closed";
  subject: string;
  description: string;
  created_by: string;
  updated_by: string;
  created_at: string;
  updated_at: string;
};

export type ConsentRecord = {
  consent_event_id: string;
  managed_account_id: string | null;
  consent_type: "ai_processing" | "analytics_storage" | "aggregate_learning" | "provider_data_processing" | "marketing_communications";
  decision: "granted" | "denied" | "revoked";
  policy_version: string;
  effective_at: string;
  actor_user_id: string;
};

export type DeletionRequest = {
  id: string;
  scope: "workspace" | "account" | "content" | "user";
  target_id: string;
  state: "requested" | "tombstoned" | "purging" | "provider_pending" | "completed" | "failed";
  requested_by: string | null;
  requested_at: string;
  tombstoned_at: string | null;
  completed_at: string | null;
  manifest_version: string;
  purge_jobs_total: string;
  purge_jobs_confirmed: string;
};

function requireRow<T>(row: T | undefined): T {
  if (!row) throw new Error("enterprise operation returned no row");
  return row;
}

export async function listAgencyClients(client: PoolClient, principal: AuthPrincipal) {
  const result = await client.query<AgencyClient>(
    "select * from growth.list_agency_clients($1)",
    [principal.workspaceId]
  );
  return result.rows;
}

export async function setAgencyClient(
  client: PoolClient,
  principal: AuthPrincipal,
  input: { clientWorkspaceId: string; label: string; state: AgencyClient["state"] }
) {
  const result = await client.query(
    "select * from growth.set_agency_client($1, $2, $3, $4)",
    [principal.workspaceId, input.clientWorkspaceId, input.label, input.state]
  );
  return requireRow(result.rows[0]);
}

export async function listSupportCases(client: PoolClient, principal: AuthPrincipal) {
  const result = await client.query<SupportCase>(
    "select * from growth.list_support_cases($1, $2)",
    [principal.workspaceId, 50]
  );
  return result.rows;
}

export async function createSupportCase(
  client: PoolClient,
  principal: AuthPrincipal,
  input: Pick<SupportCase, "category" | "priority" | "subject" | "description">
) {
  const result = await client.query<SupportCase>(
    "select * from growth.create_support_case($1, $2, $3, $4, $5)",
    [principal.workspaceId, input.category, input.priority, input.subject, input.description]
  );
  return requireRow(result.rows[0]);
}

export async function updateSupportCase(
  client: PoolClient,
  principal: AuthPrincipal,
  input: { caseId: string; note: string; state?: SupportCase["state"] | null }
) {
  const result = await client.query<SupportCase>(
    "select * from growth.update_support_case($1, $2, $3, $4)",
    [principal.workspaceId, input.caseId, input.note, input.state ?? null]
  );
  return requireRow(result.rows[0]);
}

export async function listLatestConsents(client: PoolClient, principal: AuthPrincipal) {
  const result = await client.query<ConsentRecord>(
    "select * from growth.list_latest_consents($1)",
    [principal.workspaceId]
  );
  return result.rows;
}

export async function recordWorkspaceConsent(
  client: PoolClient,
  principal: AuthPrincipal,
  input: {
    managedAccountId?: string | null;
    consentType: ConsentRecord["consent_type"];
    decision: ConsentRecord["decision"];
    policyVersion: string;
  }
) {
  const result = await client.query(
    "select * from growth.record_workspace_consent($1, $2, $3, $4, $5)",
    [principal.workspaceId, input.managedAccountId ?? null, input.consentType, input.decision, input.policyVersion]
  );
  return requireRow(result.rows[0]);
}

export async function listDeletionRequests(client: PoolClient, principal: AuthPrincipal) {
  const result = await client.query<DeletionRequest>(
    "select * from growth.list_deletion_requests($1, $2)",
    [principal.workspaceId, 50]
  );
  return result.rows;
}

export async function createDeletionRequest(
  client: PoolClient,
  principal: AuthPrincipal,
  input: { scope: DeletionRequest["scope"]; targetId: string; manifestVersion: string }
) {
  const result = await client.query(
    "select * from growth.create_deletion_request($1, $2, $3, $4)",
    [principal.workspaceId, input.scope, input.targetId, input.manifestVersion]
  );
  return requireRow(result.rows[0]);
}

export async function tombstoneDeletionRequest(
  client: PoolClient,
  principal: AuthPrincipal,
  requestId: string
) {
  const result = await client.query(
    "select * from growth.tombstone_deletion_request($1, $2)",
    [principal.workspaceId, requestId]
  );
  return requireRow(result.rows[0]);
}
