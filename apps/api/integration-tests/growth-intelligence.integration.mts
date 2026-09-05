import { randomUUID } from "node:crypto";
import assert from "node:assert/strict";
import pg, { type PoolClient } from "pg";
import { db } from "../src/db.js";

const { Pool } = pg;
function requiredDatabaseUrl(name: "MIGRATOR_DATABASE_URL") {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required for Growth Intelligence integration fixtures`);
  return value;
}

const workspaceId = "b0000000-0000-4000-8000-000000000001";
const userId = "a0000000-0000-4000-8000-000000000001";
const managedAccountId = randomUUID();
const connectionId = randomUUID();
const socialAccountId = randomUUID();
const observationIds = [randomUUID(), randomUUID(), randomUUID()];
const noSignalManagedAccountId = randomUUID();
const noSignalConnectionId = randomUUID();
const noSignalSocialAccountId = randomUUID();
const providerAccountId = `growth-intelligence-${socialAccountId}`;
const noSignalProviderAccountId = `growth-intelligence-no-signal-${noSignalSocialAccountId}`;

const migrator = new Pool({ connectionString: requiredDatabaseUrl("MIGRATOR_DATABASE_URL"), max: 1 });

async function withMigrator<T>(fn: (client: PoolClient) => Promise<T>) {
  const client = await migrator.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceId]);
    await client.query("SELECT set_config('app.user_id', $1, true)", [userId]);
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

const appClient = await db.connect();
try {
  await withMigrator(async (client) => {
    await client.query(
      `insert into growth.managed_accounts
        (id, workspace_id, owner_type, authority_status, contribution_eligibility)
       values ($1,$2,'direct','contractually_granted','eligible')`,
      [managedAccountId, workspaceId]
    );
    await client.query(
      `insert into growth.platform_connections
        (id, workspace_id, managed_account_id, platform, state)
       values ($1,$2,$3,'youtube','connected')`,
      [connectionId, workspaceId, managedAccountId]
    );
    await client.query(
      `insert into growth.social_accounts
        (id, workspace_id, managed_account_id, platform_connection_id, platform, provider_account_id, handle, account_type, market, timezone)
       values ($1,$2,$3,$4,'youtube',$5,'@growth-intelligence','channel','US','America/Los_Angeles')`,
      [socialAccountId, workspaceId, managedAccountId, connectionId, providerAccountId]
    );
    await client.query(
      `insert into growth.managed_accounts
        (id, workspace_id, owner_type, authority_status, contribution_eligibility)
       values ($1,$2,'direct','contractually_granted','eligible')`,
      [noSignalManagedAccountId, workspaceId]
    );
    await client.query(
      `insert into growth.platform_connections
        (id, workspace_id, managed_account_id, platform, state)
       values ($1,$2,$3,'youtube','connected')`,
      [noSignalConnectionId, workspaceId, noSignalManagedAccountId]
    );
    await client.query(
      `insert into growth.social_accounts
        (id, workspace_id, managed_account_id, platform_connection_id, platform, provider_account_id, handle, account_type, market, timezone)
       values ($1,$2,$3,$4,'youtube',$5,'@growth-intelligence-empty','channel','US','America/Los_Angeles')`,
      [noSignalSocialAccountId, workspaceId, noSignalManagedAccountId, noSignalConnectionId, noSignalProviderAccountId]
    );

    const values = [
      { id: observationIds[0], day: "2026-09-01", value: 100 },
      { id: observationIds[1], day: "2026-09-02", value: 105 },
      { id: observationIds[2], day: "2026-09-03", value: 160 }
    ];

    for (const item of values) {
      await client.query(
        `insert into growth.metric_observations
          (id, workspace_id, social_account_id, provider_content_id, metric_name, raw_value, unit,
           observed_at, provider_effective_at, source_timezone, provider_api_version, source_schema_version,
           collection_method, raw_payload_ref, adapter_version, provider_product, provider_object_type,
           metric_semantic_version, source_range_start, source_range_end, collected_at,
           authorization_class, retention_deadline, refresh_required_by, completeness_status,
           freshness_status, collection_run_id, idempotency_key)
         values
          ($1,$2,$3,$4,'views',$5,'count',
           ($6 || 'T07:00:00Z')::timestamptz, ($6 || 'T07:00:00Z')::timestamptz,
           'America/Los_Angeles','youtube-analytics-v2','youtube-source-v1','polling',
           $7,'youtube-adapter-v1','youtube','channel_daily_report',
           'youtube.analytics.views.provider-day-2026-08-24.v2',
           ($6 || 'T07:00:00Z')::timestamptz, ((($6::date + 1)::text) || 'T07:00:00Z')::timestamptz,
           now(),'authorized_account',now() + interval '30 days',now() + interval '29 days',
           'complete','fresh',gen_random_uuid(),$8)`,
        [
          item.id,
          workspaceId,
          socialAccountId,
          `channel:${providerAccountId}`,
          item.value,
          item.day,
          `sha256:test-${item.id}`,
          `growth-intelligence-${item.id}`
        ]
      );
    }
  });

  await appClient.query("BEGIN");
  await appClient.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceId]);
  await appClient.query("SELECT set_config('app.user_id', $1, true)", [userId]);

  const first = await appClient.query<{
    signal_id: string | null;
    insight_id: string | null;
    opportunity_id: string | null;
    result_status: string;
    observations_used: number;
    delta_ratio: string;
  }>("select * from growth.recompute_youtube_growth_intelligence($1)", [socialAccountId]);

  assert.equal(first.rows[0]?.result_status, "opportunity_created");
  assert.ok(first.rows[0]?.signal_id);
  assert.ok(first.rows[0]?.insight_id);
  assert.ok(first.rows[0]?.opportunity_id);
  assert.equal(first.rows[0]?.observations_used, 3);
  assert.equal(Number(first.rows[0]?.delta_ratio), 0.5609756097560976);

  const second = await appClient.query<{
    signal_id: string | null;
    insight_id: string | null;
    opportunity_id: string | null;
    result_status: string;
  }>("select * from growth.recompute_youtube_growth_intelligence($1)", [socialAccountId]);

  assert.equal(second.rows[0]?.signal_id, first.rows[0]?.signal_id);
  assert.equal(second.rows[0]?.insight_id, first.rows[0]?.insight_id);
  assert.equal(second.rows[0]?.opportunity_id, first.rows[0]?.opportunity_id);
  assert.equal(second.rows[0]?.result_status, "opportunity_created");

  const noSignal = await appClient.query<{
    signal_id: string | null;
    insight_id: string | null;
    opportunity_id: string | null;
    result_status: string;
    observations_used: number;
    delta_ratio: string | null;
  }>("select * from growth.recompute_youtube_growth_intelligence($1)", [noSignalSocialAccountId]);
  assert.equal(noSignal.rows[0]?.result_status, "insufficient_signal");
  assert.equal(noSignal.rows[0]?.signal_id, null);
  assert.equal(noSignal.rows[0]?.insight_id, null);
  assert.equal(noSignal.rows[0]?.opportunity_id, null);
  assert.equal(noSignal.rows[0]?.observations_used, 0);
  assert.equal(noSignal.rows[0]?.delta_ratio, null);

  await appClient.query("COMMIT");

  const counts = await withMigrator((client) =>
    client.query<{ signals: string; insights: string; opportunities: string }>(
      `select
         (select count(*) from growth.factual_signals where workspace_id=$1 and social_account_id=$2) as signals,
         (select count(*) from growth.insights where workspace_id=$1 and source_signal_id=$3) as insights,
         (select count(*) from growth.opportunities where workspace_id=$1 and source_signal_id=$3) as opportunities`,
      [workspaceId, socialAccountId, first.rows[0]?.signal_id]
    )
  );
  assert.deepEqual(counts.rows[0], { signals: "1", insights: "1", opportunities: "1" });
} finally {
  try {
    await appClient.query("ROLLBACK");
  } catch { /* no-op */ }
  appClient.release();

  await withMigrator(async (client) => {
    await client.query(
      `delete from growth.opportunity_evidence
        where workspace_id=$1 and opportunity_id in (
          select id from growth.opportunities where workspace_id=$1 and social_account_id=$2
        )`,
      [workspaceId, socialAccountId]
    );
    await client.query(
      `delete from growth.insight_evidence
        where workspace_id=$1 and insight_id in (
          select id from growth.insights where workspace_id=$1 and social_account_id=$2
        )`,
      [workspaceId, socialAccountId]
    );
    await client.query("delete from growth.opportunities where workspace_id=$1 and social_account_id=$2", [workspaceId, socialAccountId]);
    await client.query("delete from growth.insights where workspace_id=$1 and social_account_id=$2", [workspaceId, socialAccountId]);
    await client.query("delete from growth.factual_signals where workspace_id=$1 and social_account_id=$2", [workspaceId, socialAccountId]);
    await client.query("delete from growth.metric_observations where workspace_id=$1 and social_account_id=$2", [workspaceId, socialAccountId]);
    await client.query("delete from growth.social_accounts where workspace_id=$1 and id=$2", [workspaceId, noSignalSocialAccountId]);
    await client.query("delete from growth.platform_connections where workspace_id=$1 and id=$2", [workspaceId, noSignalConnectionId]);
    await client.query("delete from growth.managed_accounts where workspace_id=$1 and id=$2", [workspaceId, noSignalManagedAccountId]);
    await client.query("delete from growth.social_accounts where workspace_id=$1 and id=$2", [workspaceId, socialAccountId]);
    await client.query("delete from growth.platform_connections where workspace_id=$1 and id=$2", [workspaceId, connectionId]);
    await client.query("delete from growth.managed_accounts where workspace_id=$1 and id=$2", [workspaceId, managedAccountId]);
  });
  await migrator.end();
  await db.end();
}
