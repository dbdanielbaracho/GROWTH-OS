import { randomUUID } from "node:crypto";
import pg, { type PoolClient } from "pg";
import { buildApp } from "../src/app.js";
import { db } from "../src/db.js";

const { Pool } = pg;

function requiredDatabaseUrl(name: "MIGRATOR_DATABASE_URL") {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required for Opportunity Radar integration fixtures`);
  return value;
}

const legit = {
  "x-user-id": "a0000000-0000-4000-8000-000000000001",
  "x-workspace-id": "b0000000-0000-4000-8000-000000000001"
};
const victimWorkspace = "b0000000-0000-4000-8000-000000000002";

let failures = 0;
function check(name: string, ok: boolean, detail?: unknown) {
  if (ok) console.log(`PASS: ${name}`);
  else { failures++; console.error(`FAIL: ${name}`, detail ?? ""); }
}

const app = buildApp(false);
const migrator = new Pool({ connectionString: requiredDatabaseUrl("MIGRATOR_DATABASE_URL"), max: 1 });
const activeOpportunityId = randomUUID();
const expiredOpportunityId = randomUUID();
const evidenceId = randomUUID();

async function withMigratorContext<T>(workspaceId: string, fn: (client: PoolClient) => Promise<T>) {
  const client = await migrator.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceId]);
    await client.query("SELECT set_config('app.user_id', $1, true)", [legit["x-user-id"]]);
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

try {
  await withMigratorContext(legit["x-workspace-id"], async (client) => {
    await client.query(
      `insert into growth.opportunities
        (id, workspace_id, social_account_id, market, platform, status, score, confidence, ranking_version, expires_at)
       values
        ($1, $2, null, 'US', 'test-platform', 'active', 91, '{"level":"high"}'::jsonb, 'radar-it-v1', now() + interval '1 day'),
        ($3, $2, null, 'US', 'test-platform', 'expired', 99, '{"level":"high"}'::jsonb, 'radar-it-v1', now() - interval '1 minute')`,
      [activeOpportunityId, legit["x-workspace-id"], expiredOpportunityId]
    );
    await client.query(
      `insert into growth.opportunity_evidence
        (id, workspace_id, opportunity_id, source_class, evidence_ref, observed_at)
       values ($1, $2, $3, 'owned', $4, now())`,
      [evidenceId, legit["x-workspace-id"], activeOpportunityId, `integration:${activeOpportunityId}`]
    );
  });

  const listRes = await app.inject({ method: "GET", url: "/v1/opportunities", headers: legit });
  const listed = listRes.json()?.opportunities ?? [];
  check("(1) Opportunity Radar list succeeds through app_runtime", listRes.statusCode === 200, listRes.body);
  check("(2) active opportunity is listed", listed.some((row: any) => row.id === activeOpportunityId), listed);
  check("(3) expired opportunity is excluded", !listed.some((row: any) => row.id === expiredOpportunityId), listed);
  const activeSummary = listed.find((row: any) => row.id === activeOpportunityId);
  check("(4) list exposes the real evidence count", activeSummary?.evidence_count === 1, activeSummary);

  const detailRes = await app.inject({
    method: "GET", url: `/v1/opportunities/${activeOpportunityId}`, headers: legit
  });
  const detail = detailRes.json();
  check("(5) same-tenant opportunity detail succeeds", detailRes.statusCode === 200, detailRes.body);
  check("(6) detail returns stored evidence without synthesis",
    detail?.evidence?.length === 1 && detail.evidence[0]?.evidence_ref === `integration:${activeOpportunityId}`, detail);
  check("(7) opportunity without social_account_id does not invent related insights",
    Array.isArray(detail?.related_insights) && detail.related_insights.length === 0, detail);

  const expiredDetailRes = await app.inject({
    method: "GET", url: `/v1/opportunities/${expiredOpportunityId}`, headers: legit
  });
  check("(8) expired opportunity detail is not exposed", expiredDetailRes.statusCode === 404, expiredDetailRes.body);

  const invalidRes = await app.inject({ method: "GET", url: "/v1/opportunities/not-a-uuid", headers: legit });
  check("(9) malformed opportunity identifier is rejected", invalidRes.statusCode === 400, invalidRes.body);

  const victimLookup = await withMigratorContext(victimWorkspace, async (client) =>
    client.query<{ id: string }>(`select id from growth.opportunities where workspace_id = $1 limit 1`, [victimWorkspace])
  );
  const victimOpportunityId = victimLookup.rows[0]?.id;
  check("(setup) victim workspace has an opportunity fixture", !!victimOpportunityId, victimLookup.rows);

  if (victimOpportunityId) {
    const crossTenantRes = await app.inject({
      method: "GET", url: `/v1/opportunities/${victimOpportunityId}`, headers: legit
    });
    check("(10) cross-tenant opportunity detail is hidden as not_found", crossTenantRes.statusCode === 404, crossTenantRes.body);
  }
} finally {
  try {
    await withMigratorContext(legit["x-workspace-id"], async (client) => {
      await client.query(`delete from growth.opportunity_evidence where id = $1`, [evidenceId]);
      await client.query(`delete from growth.opportunities where id = any($1::uuid[])`, [[activeOpportunityId, expiredOpportunityId]]);
    });
  } catch (error) {
    console.error("WARN: Opportunity Radar integration cleanup failed", error);
  }
  await app.close();
  await db.end();
  await migrator.end();
}

process.exit(failures > 0 ? 1 : 0);
