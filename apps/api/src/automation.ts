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

export type AutomationExecutionStatus =
  | "not_ready"
  | "ready"
  | "executing"
  | "succeeded"
  | "needs_input"
  | "failed";

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
  execution_status: AutomationExecutionStatus;
  execution_result_ref: string | null;
  execution_error_class: string | null;
  execution_started_at: string | null;
  executed_at: string | null;
  execution_attempts: number;
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
  const row = result.rows[0];
  if (!row) throw new Error("automation helper returned no row");
  return row;
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
  const row = result.rows[0];
  if (!row) throw new Error("automation helper returned no row");
  return row;
}

export async function listAutomationActionRequests(
  client: PoolClient,
  principal: AuthPrincipal,
  limit = 50
): Promise<AutomationActionRequest[]> {
  const result = await client.query<AutomationActionRequest>(
    "select * from growth.list_automation_action_requests_v2($1, $2)",
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
    actionPayload?: Record<string, unknown>;
  }
): Promise<AutomationActionRequest> {
  const result = await client.query<AutomationActionRequest>(
    "select * from growth.create_automation_action_request_v2($1, $2, $3, $4, $5, $6::jsonb)",
    [
      principal.workspaceId,
      input.actionCode,
      input.targetRef,
      input.evidenceRef,
      input.note ?? null,
      JSON.stringify(input.actionPayload ?? {})
    ]
  );
  const row = result.rows[0];
  if (!row) throw new Error("automation helper returned no row");
  return row;
}

export async function decideAutomationActionRequest(
  client: PoolClient,
  principal: AuthPrincipal,
  requestId: string,
  decision: "approve" | "reject" | "cancel",
  note?: string | null
): Promise<AutomationActionRequest> {
  const result = await client.query<AutomationActionRequest>(
    "select * from growth.decide_automation_action_request_v2($1, $2, $3, $4)",
    [principal.workspaceId, requestId, decision, note ?? null]
  );
  const row = result.rows[0];
  if (!row) throw new Error("automation helper returned no row");
  return row;
}

export async function claimAutomationActionExecution(
  client: PoolClient,
  principal: AuthPrincipal,
  requestId: string
): Promise<AutomationActionRequest> {
  const result = await client.query<AutomationActionRequest>(
    "select * from growth.claim_automation_action_execution($1, $2)",
    [principal.workspaceId, requestId]
  );
  const row = result.rows[0];
  if (!row) throw new Error("automation claim returned no row");
  return row;
}

export async function finalizeAutomationActionExecution(
  client: PoolClient,
  principal: AuthPrincipal,
  requestId: string,
  input: {
    executionStatus: "succeeded" | "needs_input" | "failed";
    resultRef?: string | null;
    errorClass?: string | null;
  }
): Promise<AutomationActionRequest> {
  const result = await client.query<AutomationActionRequest>(
    "select * from growth.finalize_automation_action_execution($1, $2, $3, $4, $5)",
    [
      principal.workspaceId,
      requestId,
      input.executionStatus,
      input.resultRef ?? null,
      input.errorClass ?? null
    ]
  );
  const row = result.rows[0];
  if (!row) throw new Error("automation finalization returned no row");
  return row;
}
