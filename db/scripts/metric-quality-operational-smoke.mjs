import process from 'node:process';
import pg from 'pg';

const { Client } = pg;
const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) {
  console.error('DATABASE_URL is required');
  process.exit(2);
}

const client = new Client({ connectionString: databaseUrl });
let inTransaction = false;

try {
  await client.connect();
  const target = await client.query(
    'select current_database() as database, current_user as user',
  );
  console.log('Metric quality operational smoke target:', target.rows[0]);

  await client.query('BEGIN');
  inTransaction = true;

  const principal = await client.query(`
    select m.workspace_id, m.user_id
      from growth.memberships m
      join growth.users u on u.id = m.user_id
      join growth.workspaces w on w.id = m.workspace_id
     where m.status = 'active'
       and u.status = 'active'
       and w.status = 'active'
     order by m.created_at asc nulls last, m.workspace_id, m.user_id
     limit 1
  `);

  if (principal.rowCount !== 1) {
    throw new Error('metric quality operational smoke requires one active production membership');
  }

  const { workspace_id: workspaceId, user_id: userId } = principal.rows[0];
  await client.query(
    `select set_config('app.user_id', $1, true),
            set_config('app.workspace_id', $2, true)`,
    [userId, workspaceId],
  );

  const result = await client.query(
    `select count(*)::bigint as anomaly_count
       from growth.list_metric_quality_anomalies(
         $1::uuid,
         now() - interval '7 days',
         now()
       )`,
    [workspaceId],
  );

  const anomalyCount = result.rows[0]?.anomaly_count;
  if (anomalyCount === undefined || anomalyCount === null) {
    throw new Error('metric quality operational smoke returned no count');
  }

  await client.query('ROLLBACK');
  inTransaction = false;

  console.log(
    `Production metric quality operational smoke: PASS helper executed; anomaly_count=${anomalyCount}; rollback complete`,
  );
} catch (error) {
  if (inTransaction) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // Preserve the original smoke failure.
    }
  }
  throw error;
} finally {
  await client.end();
}
