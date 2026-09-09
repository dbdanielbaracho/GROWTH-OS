import type { PoolClient } from "pg";
import type { AuthPrincipal } from "./auth.js";

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

function requireRow<T>(row: T | undefined): T {
  if (!row) throw new Error("commercial helper returned no row");
  return row;
}

export async function getWorkspaceEntitlements(
  client: PoolClient,
  principal: AuthPrincipal
): Promise<WorkspaceEntitlements> {
  const result = await client.query<WorkspaceEntitlements>(
    "select * from growth.get_workspace_entitlements($1)",
    [principal.workspaceId]
  );
  return requireRow(result.rows[0]);
}

export async function setWorkspaceSubscription(
  client: PoolClient,
  principal: AuthPrincipal,
  input: {
    planCode: "free" | "pro" | "enterprise";
    status: "trialing" | "active" | "past_due" | "cancelled";
    providerCustomerRef?: string | null;
    providerSubscriptionRef?: string | null;
  }
) {
  const result = await client.query(
    "select * from growth.set_workspace_subscription($1, $2, $3, $4, $5)",
    [
      principal.workspaceId,
      input.planCode,
      input.status,
      input.providerCustomerRef ?? null,
      input.providerSubscriptionRef ?? null
    ]
  );
  return requireRow(result.rows[0]);
}

export async function getEnterprisePolicy(
  client: PoolClient,
  principal: AuthPrincipal
): Promise<EnterprisePolicy> {
  const result = await client.query<EnterprisePolicy>(
    "select * from growth.get_enterprise_policy($1)",
    [principal.workspaceId]
  );
  return requireRow(result.rows[0]);
}

export async function setEnterprisePolicy(
  client: PoolClient,
  principal: AuthPrincipal,
  input: {
    retentionDays: number;
    supportTier: "standard" | "priority" | "dedicated";
    legalAcceptanceRef?: string | null;
  }
): Promise<EnterprisePolicy> {
  const result = await client.query<EnterprisePolicy>(
    "select * from growth.set_enterprise_policy($1, $2, $3, $4)",
    [
      principal.workspaceId,
      input.retentionDays,
      input.supportTier,
      input.legalAcceptanceRef ?? null
    ]
  );
  return requireRow(result.rows[0]);
}
