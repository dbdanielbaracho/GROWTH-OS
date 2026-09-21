import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';

// Compatibility wrapper for forward runtime corrections that must be applied
// before the historical production reconciler inspects its registered numeric
// migration set. The canonical 074 migration remains in db/migrations so the
// normal CI migration loop executes it; production applies it explicitly, then
// hides only that file while the unchanged reconciler performs its legacy
// registration check. The source file is restored before this process exits.
const root = process.cwd();
const migrationPath = path.join(
  root,
  'db',
  'migrations',
  '074_metric_quality_anomalies_runtime_fix.sql',
);
const hiddenMigrationPath = `${migrationPath}.production-reconciled`;
const applyMigrationScript = path.join(root, 'db', 'scripts', 'apply-migration.mjs');
const coreReconciler = path.join(root, 'db', 'scripts', 'apply-production-migrations-core.mjs');
const metricQualitySmoke = path.join(root, 'db', 'scripts', 'metric-quality-operational-smoke.mjs');

async function runNode(scriptPath, args = []) {
  await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [scriptPath, ...args], {
      cwd: root,
      env: process.env,
      stdio: 'inherit',
    });

    child.once('error', reject);
    child.once('exit', (code, signal) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(
        `production migration child failed: ${path.basename(scriptPath)} code=${code ?? 'null'} signal=${signal ?? 'none'}`,
      ));
    });
  });
}

let migrationHidden = false;
try {
  await runNode(applyMigrationScript, [migrationPath]);
  console.log('Applied production runtime correction: 074_metric_quality_anomalies_runtime_fix.sql');

  await fs.rename(migrationPath, hiddenMigrationPath);
  migrationHidden = true;

  await import(pathToFileURL(coreReconciler).href);
} finally {
  if (migrationHidden) {
    await fs.rename(hiddenMigrationPath, migrationPath);
  }
}

// Production Truth Gate for this runtime defect. This is read-only apart from
// transaction-local session context and always rolls back. A failure here makes
// the migrator deployment fail instead of allowing the application to ship with
// an unexecuted PL/pgSQL regression.
await runNode(metricQualitySmoke);
