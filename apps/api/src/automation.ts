import type { PoolClient } from "pg";
import type { AuthPrincipal } from "./auth.js";

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

export async function getAutomationPolicy(
  client: PoolClient,
  principal: AuthPrincipal
): Promise<AutomationPolicy> {
  const result = await client.query<AutomationPolicy>(
    "select * from growth.get_automation_policy($1)",
    [principal.workspaceId]
  );
  return result.rows[0];
}

export async function setAutomationPolicy(
  client: PoolClient,
  principal: AuthPrincipal,
  input: {
    mode: "approval_required" | "disabled";
    dailyRequestLimit: number;
    killSwitch: boolean;
  }
): Promise<AutomationPolicy> {
  const result = await client.query<AutomationPolicy>(
    "select * from growth.set_automation_policy($1, $2, $3, $4)",
    [principal.workspaceId, input.mode, input.dailyRequestLimit, input.killSwitch]
  );
  return result.rows[0];
}

export async function listAutomationActionRequests(
  client: PoolClient,
  principal: AuthPrincipal,
  limit = 50
): Promise<AutomationActionRequest[]> {
  const result = await client.query<AutomationActionRequest>(
    "select * from growth.list_automation_action_requests($1, $2)",
    [principal.workspaceId, Math.min(Math.max(limit, 1), 100)]
  );
  return result.rows;
}

export async function createAutomationActionRequest(
  client: PoolClient,
  principal: AuthPrincipal,
  input: {
    actionCode: AutomationActionRequest["action_code"];
    targetRef: string;
    evidenceRef: string;
    note?: string | null;
  }
): Promise<AutomationActionRequest> {
  const result = await client.query<AutomationActionRequest>(
    "select * from growth.create_automation_action_request($1, $2, $3, $4, $5)",
    [
      principal.workspaceId,
      input.actionCode,
      input.targetRef,
      input.evidenceRef,
      input.note ?? null
    ]
  );
  return result.rows[0];
}

export async function decideAutomationActionRequest(
  client: PoolClient,
  principal: AuthPrincipal,
  requestId: string,
  decision: "approve" | "reject" | "cancel",
  note?: string | null
): Promise<AutomationActionRequest> {
  const result = await client.query<AutomationActionRequest>(
    "select * from growth.decide_automation_action_request($1, $2, $3, $4)",
    [principal.workspaceId, requestId, decision, note ?? null]
  );
  return result.rows[0];
}
