import type { PoolClient } from "pg";
import type { AuthPrincipal } from "./auth.js";

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

export async function listExperiments(client: PoolClient, principal: AuthPrincipal, limit = 50) {
  const safeLimit = Math.min(Math.max(limit, 1), 100);
  const result = await client.query<Experiment>(
    "select * from growth.list_experiments($1, $2)",
    [principal.workspaceId, safeLimit]
  );
  return result.rows;
}

export async function createExperiment(
  client: PoolClient,
  principal: AuthPrincipal,
  opportunityId: string | null,
  name: string,
  hypothesis: string,
  decisionRule: string
) {
  const result = await client.query<Experiment>(
    "select * from growth.create_experiment($1, $2, $3, $4, $5)",
    [principal.workspaceId, opportunityId, name, hypothesis, decisionRule]
  );
  const experiment = result.rows[0];
  if (!experiment) throw new Error("experiment creation returned no row");
  return experiment;
}

export async function addExperimentVariant(
  client: PoolClient,
  principal: AuthPrincipal,
  experimentId: string,
  label: string,
  lineage: Record<string, unknown>
) {
  const result = await client.query<ExperimentVariant>(
    "select * from growth.add_experiment_variant($1, $2, $3, $4::jsonb)",
    [principal.workspaceId, experimentId, label, JSON.stringify(lineage)]
  );
  const variant = result.rows[0];
  if (!variant) throw new Error("experiment variant creation returned no row");
  return variant;
}

export async function recordExperimentFeedback(
  client: PoolClient,
  principal: AuthPrincipal,
  experimentId: string,
  variantId: string,
  outcome: "winner" | "loser" | "inconclusive",
  evidenceRef: string | null,
  note: string | null
) {
  const result = await client.query(
    "select * from growth.record_experiment_feedback($1, $2, $3, $4, $5, $6)",
    [principal.workspaceId, experimentId, variantId, outcome, evidenceRef, note]
  );
  return result.rows[0];
}
