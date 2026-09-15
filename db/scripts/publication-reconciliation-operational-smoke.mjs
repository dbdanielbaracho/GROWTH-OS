import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import pg from 'pg';

const { Client } = pg;
const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) {
  console.error('DATABASE_URL is required');
  process.exit(2);
}

const smokePath = path.resolve('db/tests/046_publication_reconciliation.sql');

function normalizeSqlForPgDriver(sql, filePath) {
  return sql
    .split('\n')
    .map((line) => {
      const trimmed = line.trim();
      if (/^\\set\s+ON_ERROR_STOP\s+(?:on|off)\s*$/i.test(trimmed)) return '';
      if (/^\\/.test(trimmed)) {
        throw new Error(`Unsupported psql meta-command in ${filePath}: ${trimmed}`);
      }
      return line;
    })
    .join('\n');
}

const client = new Client({ connectionString: databaseUrl });

try {
  await client.connect();
  const target = await client.query(
    'select current_database() as database, current_user as user',
  );
  console.log('Publication reconciliation operational smoke target:', target.rows[0]);

  const sql = normalizeSqlForPgDriver(
    await fs.readFile(smokePath, 'utf8'),
    smokePath,
  );
  await client.query(sql);

  console.log(
    'Production publication reconciliation operational smoke: PASS ambiguous -> needs_user_action -> matched -> confirmed; immutable replay rejected; rollback complete',
  );
} finally {
  await client.end();
}
