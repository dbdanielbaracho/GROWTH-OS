import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import pg from 'pg';

const { Client } = pg;

const migrationPath = process.argv[2];

if (!migrationPath) {
  console.error('Usage: node db/scripts/apply-migration.mjs <path-to-sql>');
  process.exit(2);
}

if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL is required');
  process.exit(2);
}

const absolutePath = path.resolve(migrationPath);
const sql = await fs.readFile(absolutePath, 'utf8');

const client = new Client({ connectionString: process.env.DATABASE_URL });

try {
  await client.connect();
  const server = await client.query('select version() as version, current_database() as database, current_user as user');
  console.log(server.rows[0]);
  await client.query(sql);
  console.log(`Applied migration: ${absolutePath}`);
} finally {
  await client.end();
}
