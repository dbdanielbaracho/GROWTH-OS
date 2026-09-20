import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import pg from "pg";

const { Pool } = pg;
const sourceUrl = process.env.SOURCE_DATABASE_URL;
const restoreUrl = process.env.RESTORE_DATABASE_URL;
const restoreAppUrl = process.env.RESTORE_APP_DATABASE_URL;
const ack = process.env.PHASE11_RESTORE_DRILL_ACK;
const environment = process.env.PHASE11_RESTORE_DRILL_ENV;

if (!sourceUrl || !restoreUrl || !restoreAppUrl) {
  throw new Error("SOURCE_DATABASE_URL, RESTORE_DATABASE_URL and RESTORE_APP_DATABASE_URL are required");
}
if (ack !== "RESTORE_TO_DISPOSABLE_QUARANTINE" || environment !== "ci_quarantine") {
  throw new Error("restore drill requires the explicit disposable-quarantine acknowledgement");
}

const source = new URL(sourceUrl);
const restore = new URL(restoreUrl);
const restoreApp = new URL(restoreAppUrl);
const sourceDatabase = source.pathname.slice(1);
const restoreDatabase = restore.pathname.slice(1);
if (
  !/^growth_os_restore_[a-z0-9_]+$/.test(restoreDatabase)
  || sourceDatabase === restoreDatabase
  || source.host !== restore.host
  || restore.host !== restoreApp.host
  || restoreDatabase !== restoreApp.pathname.slice(1)
) {
  throw new Error("restore target must be a distinct growth_os_restore_* database on the CI quarantine cluster");
}

const maintenance = new URL(sourceUrl);
maintenance.pathname = "/postgres";
const sourcePool = new Pool({ connectionString: sourceUrl });
const maintenancePool = new Pool({ connectionString: maintenance.toString() });
let restoreAdminPool;
let restoreRuntimePool;
const tempDirectory = await mkdtemp(join(tmpdir(), "growth-os-restore-drill-"));
const dumpPath = join(tempDirectory, "source.dump");
const workspaceId = "b0000000-0000-4000-8000-000000000001";
const userId = "a0000000-0000-4000-8000-000000000001";
const contentId = randomUUID();
const deletionRequestId = randomUUID();

function run(command, args, databaseUrl) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, PGDATABASE: databaseUrl }
    });
    let stderr = "";
    child.stderr.on("data", (chunk) => { stderr += String(chunk); });
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} failed with exit ${code}: ${stderr.slice(-2000)}`));
    });
  });
}

async function dropQuarantineDatabase() {
  await maintenancePool.query(
    `select pg_terminate_backend(pid) from pg_stat_activity where datname = $1 and pid <> pg_backend_pid()`,
    [restoreDatabase]
  );
  await maintenancePool.query(`drop database if exists "${restoreDatabase}"`);
}

async function tenantCanRead(pool) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("select set_config('app.workspace_id', $1, true)", [workspaceId]);
    await client.query("select set_config('app.user_id', $1, true)", [userId]);
    const result = await client.query(
      "select id from growth.content_items where workspace_id = $1 and id = $2",
      [workspaceId, contentId]
    );
    await client.query("rollback");
    return result.rowCount === 1;
  } finally {
    client.release();
  }
}

async function recordDeletion(pool) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query(
      `insert into growth.deletion_requests
         (id, workspace_id, requested_by, scope, target_id, state, manifest_version)
       values ($1, $2, $3, 'content', $4, 'requested', 'phase11-restore-v1')`,
      [deletionRequestId, workspaceId, userId, contentId]
    );
    await client.query(
      `insert into growth.deletion_tombstones
         (workspace_id, target_type, target_id, deletion_request_id, effective_at)
       values ($1, 'content', $2, $3, now())`,
      [workspaceId, contentId, deletionRequestId]
    );
    await client.query(
      "update growth.deletion_requests set state = 'tombstoned' where workspace_id = $1 and id = $2",
      [workspaceId, deletionRequestId]
    );
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

try {
  await sourcePool.query(
    `insert into growth.content_items
       (id, workspace_id, objective, market, language, platform_target, source_type, status, created_by)
     values ($1, $2, 'Phase 11 restore drill', 'US', 'en', 'internal', 'manual', 'draft', $3)`,
    [contentId, workspaceId, userId]
  );

  await run("pg_dump", ["--format=custom", "--file", dumpPath], sourceUrl);
  await recordDeletion(sourcePool);

  await dropQuarantineDatabase();
  await maintenancePool.query(`create database "${restoreDatabase}" template template0`);
  await run("pg_restore", ["--exit-on-error", dumpPath], restoreUrl);

  restoreAdminPool = new Pool({ connectionString: restoreUrl });
  restoreRuntimePool = new Pool({ connectionString: restoreAppUrl });
  if (!(await tenantCanRead(restoreRuntimePool))) {
    throw new Error("pre-deletion backup did not restore the controlled tenant row");
  }

  await recordDeletion(restoreAdminPool);
  if (await tenantCanRead(restoreRuntimePool)) {
    throw new Error("replayed tombstone did not deny the restored tenant read path");
  }

  const ledger = await restoreAdminPool.query(
    `select d.state, t.deletion_request_id
       from growth.deletion_requests d
       join growth.deletion_tombstones t
         on t.workspace_id = d.workspace_id and t.deletion_request_id = d.id
      where d.workspace_id = $1 and d.id = $2 and d.target_id = $3`,
    [workspaceId, deletionRequestId, contentId]
  );
  if (ledger.rowCount !== 1 || ledger.rows[0].state !== "tombstoned") {
    throw new Error("restored deletion ledger/tombstone evidence is incomplete");
  }
  console.log("PHASE11 RESTORE DRILL PASS: pre-deletion backup restored, deletion ledger replayed, tenant read denied");
} finally {
  if (restoreRuntimePool) await restoreRuntimePool.end();
  if (restoreAdminPool) await restoreAdminPool.end();
  await dropQuarantineDatabase().catch(() => undefined);
  await sourcePool.query(
    "delete from growth.deletion_tombstones where workspace_id = $1 and deletion_request_id = $2",
    [workspaceId, deletionRequestId]
  ).catch(() => undefined);
  await sourcePool.query(
    "delete from growth.deletion_requests where workspace_id = $1 and id = $2",
    [workspaceId, deletionRequestId]
  ).catch(() => undefined);
  await sourcePool.query(
    "delete from growth.content_items where workspace_id = $1 and id = $2",
    [workspaceId, contentId]
  ).catch(() => undefined);
  await sourcePool.end();
  await maintenancePool.end();
  await rm(tempDirectory, { recursive: true, force: true });
}
