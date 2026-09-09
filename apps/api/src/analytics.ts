import type { PoolClient } from "pg";
import type { AuthPrincipal } from "./auth.js";

export async function listMetricAnalyticsSummary(
  client: PoolClient,
  principal: AuthPrincipal,
  from: string,
  to: string
) {
  const result = await client.query(
    `select *
       from growth.list_metric_analytics_summary($1, $2::timestamptz, $3::timestamptz)`,
    [principal.workspaceId, from, to]
  );
  return result.rows;
}


export async function listMetricQualityAnomalies(
  client: PoolClient,
  principal: AuthPrincipal,
  from: string,
  to: string
) {
  const result = await client.query(
    `select *
       from growth.list_metric_quality_anomalies($1, $2::timestamptz, $3::timestamptz)`,
    [principal.workspaceId, from, to]
  );
  return result.rows;
}
