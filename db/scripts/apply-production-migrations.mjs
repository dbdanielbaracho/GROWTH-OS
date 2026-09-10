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

const migrationsDir = path.resolve('db/migrations');
const client = new Client({ connectionString: databaseUrl });

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

async function functionExists(signature) {
  const result = await client.query(
    'select to_regprocedure($1) is not null as present',
    [signature],
  );
  return result.rows[0].present;
}

async function functionDefinitionContains(signature, fragment) {
  const result = await client.query(
    'select coalesce(pg_get_functiondef(to_regprocedure($1)), \'\') like $2 as present',
    [signature, `%${fragment}%`],
  );
  return result.rows[0].present;
}

async function tableExists(qualifiedName) {
  const result = await client.query(
    'select to_regclass($1) is not null as present',
    [qualifiedName],
  );
  return result.rows[0].present;
}

async function columnExists(tableName, columnName) {
  const result = await client.query(
    'select exists(select 1 from information_schema.columns where table_schema = $1 and table_name = $2 and column_name = $3) as present',
    ['growth', tableName, columnName],
  );
  return result.rows[0].present;
}

const steps = [
  {
    file: '006_identity_v1.sql',
    present: async () =>
      (await tableExists('growth.auth_identities'))
      && (await tableExists('growth.password_credentials'))
      && (await tableExists('growth.sessions'))
      && (await functionExists('growth.identity_lookup_password(text)'))
      && (await functionExists('growth.identity_create_session(uuid,text,text[],timestamptz,timestamptz,inet,text)')),
  },
  {
    file: '009_production_identity_adapter_support.sql',
    present: async () =>
      (await functionExists('growth.identity_touch_session(uuid,timestamptz)'))
      && (await functionExists('growth.identity_begin_login_attempt(text,inet,text,interval,integer,integer)'))
      && (await functionExists('growth.identity_complete_login_attempt(uuid)'))
      && (await functionExists('growth.identity_upgrade_password_hash(uuid,text,smallint)')),
  },
  {
    file: '014_youtube_integration_status.sql',
    present: () => functionExists('growth.youtube_integration_status()'),
  },
  {
    file: '015_youtube_growth_intelligence.sql',
    present: () => functionExists('growth.recompute_youtube_growth_intelligence(uuid)'),
  },
  {
    file: '016_identity_signup_verification.sql',
    present: () => functionExists('growth.identity_signup_with_verification(text,text,smallint,text,timestamptz)'),
  },
  {
    file: '017_instagram_connector_foundation.sql',
    present: () => functionExists('growth.instagram_integration_status()'),
  },
  {
    file: '018_instagram_token_lifecycle.sql',
    present: () => functionExists('growth.instagram_revoke_connection(uuid)'),
  },
  {
    file: '019_instagram_media_metrics_sync.sql',
    present: async () =>
      (await tableExists('growth.instagram_media'))
      && (await functionExists('growth.instagram_record_media(uuid,text,text,text,text,text,timestamptz,text,text,timestamptz,text,text)'))
      && (await functionExists('growth.instagram_record_metric_observation(uuid,text,text,numeric,text,timestamptz,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,text,timestamptz,timestamptz,text,text,uuid,text,text,text,text)')),
  },
  {
    file: '020_instagram_observation_idempotency_hardening.sql',
    present: () => functionDefinitionContains(
      'growth.instagram_record_metric_observation(uuid,text,text,numeric,text,timestamptz,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,text,timestamptz,timestamptz,text,text,uuid,text,text,text,text)',
      'retry-time policy metadata',
    ),
  },
  {
    file: '021_instagram_authorization_deduplication.sql',
    present: () => functionDefinitionContains(
      'growth.instagram_integration_status()',
      'LEFT JOIN LATERAL',
    ),
  },
  {
    file: '022_publication_intent_foundation.sql',
    present: () => functionExists('growth.create_publication_intent(uuid,uuid,uuid,uuid,text)'),
  },
  {
    file: '023_publication_intent_claim.sql',
    present: async () =>
      (await columnExists('publication_intents', 'current_attempt_no'))
      && (await columnExists('publication_intents', 'claim_token')),
  },
  {
    file: '024_publication_intent_finalization.sql',
    present: async () => {
      const result = await client.query("select exists(select 1 from pg_proc where pronamespace = 'growth'::regnamespace and proname = 'finalize_publication_intent') as present");
      return result.rows[0].present;
    },
  },
  {
    file: '025_publication_asset_binding.sql',
    present: () => columnExists('publication_intents', 'media_asset_id'),
  },
  {
    file: '026_publication_execution_context.sql',
    present: async () => {
      const result = await client.query("select exists(select 1 from pg_proc where pronamespace = 'growth'::regnamespace and proname = 'get_publication_execution_context') as present");
      return result.rows[0].present;
    },
  },
  {
    file: '027_publication_retry_scheduling.sql',
    present: async () =>
      (await columnExists('publication_intents', 'retry_count'))
      && (await columnExists('publication_intents', 'last_error_class')),
  },
  {
    file: '028_publication_cancellation.sql',
    present: async () =>
      (await columnExists('publication_intents', 'cancelled_at'))
      && (await columnExists('publication_intents', 'cancelled_by')),
  },
  {
    file: '029_publication_reconciliation.sql',
    present: async () => {
      const result = await client.query("select exists(select 1 from pg_proc where pronamespace = 'growth'::regnamespace and proname = 'record_publication_reconciliation') as present");
      return result.rows[0].present;
    },
  },
  {
    file: '030_publication_worker_service_principal.sql',
    present: async () =>
      (await tableExists('growth.worker_service_principals'))
      && (await columnExists('jobs', 'service_principal_id')),
  },
  {
    file: '031_publication_status_projection.sql',
    present: () => functionExists('growth.list_publication_intents(uuid,integer)'),
  },
  {
    file: '032_publication_worker_runtime_context.sql',
    present: () => functionExists('growth.complete_publication_job(uuid,uuid,text,timestamptz,text)'),
  },
  {
    file: '033_metric_analytics_summary.sql',
    present: () => functionExists('growth.list_metric_analytics_summary(uuid,timestamptz,timestamptz)'),
  },
  {
    file: '034_metric_quality_anomalies.sql',
    present: () => functionExists('growth.list_metric_quality_anomalies(uuid,timestamptz,timestamptz)'),
  },
  {
    file: '035_recommendation_feedback.sql',
    present: async () =>
      (await tableExists('growth.recommendations'))
      && (await tableExists('growth.recommendation_feedback')),
  },
  {
    file: '036_experiment_lineage.sql',
    present: async () =>
      (await tableExists('growth.experiment_variant_plans'))
      && (await tableExists('growth.experiment_feedback')),
  },
  {
    file: '037_automation_policy_control.sql',
    present: async () =>
      (await tableExists('growth.automation_policies'))
      && (await tableExists('growth.automation_action_requests')),
  },
  {
    file: '038_commercial_entitlements.sql',
    present: async () =>
      (await tableExists('growth.billing_plans'))
      && (await tableExists('growth.workspace_subscriptions'))
      && (await tableExists('growth.usage_counters'))
      && (await tableExists('growth.enterprise_policies')),
  },
  {
    file: '039_instagram_growth_intelligence.sql',
    present: () => functionExists('growth.recompute_instagram_growth_intelligence(uuid)'),
  },
  {
    file: '040_identity_account_cleanup.sql',
    present: () => tableExists('growth.identity_account_cleanup_040'),
  },
  {
    file: '041_identity_signup_runtime_privileges.sql',
    present: () => functionExists('growth.identity_signup_with_verification_v2(text,text,smallint,text,timestamptz)'),
  },
  {
    file: '042_identity_signup_fk_privileges.sql',
    present: async () => {
      const result = await client.query(`
        select
          has_schema_privilege('growth_identity_helper', 'growth', 'USAGE')
          and has_table_privilege('growth_identity_helper', 'growth.users', 'REFERENCES')
          and has_table_privilege('growth_identity_helper', 'growth.auth_identities', 'REFERENCES')
          and has_table_privilege('growth_identity_helper', 'growth.password_credentials', 'INSERT')
          as present
      `);
      return result.rows[0].present;
    },
  },
  {
    file: '043_identity_signup_fk_runtime_context.sql',
    present: async () => {
      const result = await client.query(`
        select
          has_schema_privilege('app_runtime', 'growth', 'USAGE')
          and has_schema_privilege('growth_identity_helper', 'growth', 'USAGE')
          and has_schema_privilege('growth_migrator', 'growth', 'USAGE')
          and has_table_privilege('app_runtime', 'growth.auth_identities', 'REFERENCES')
          and has_table_privilege('growth_identity_helper', 'growth.auth_identities', 'REFERENCES')
          and has_table_privilege('growth_migrator', 'growth.auth_identities', 'REFERENCES')
          as present
      `);
      return result.rows[0].present;
    },
  },
  {
    file: '044_identity_signup_smoke_cleanup.sql',
    present: () => tableExists('growth.identity_signup_smoke_cleanup_044'),
  },
  {
    file: '045_production_helper_privileges.sql',
    present: () => tableExists('growth.production_helper_privileges_045'),
  },
  {
    file: '046_managed_account_onboarding.sql',
    present: () => tableExists('growth.managed_account_onboarding_046'),
  },
  {
    file: '047_provider_status_runtime_privileges.sql',
    present: async () => {
      const result = await client.query(`
        select
          has_function_privilege('app_runtime', 'growth.youtube_integration_status()', 'EXECUTE')
          and has_function_privilege('app_runtime', 'growth.instagram_integration_status()', 'EXECUTE')
          as present
      `);
      return result.rows[0].present;
    },
  },
  {
    file: '048_provider_status_helper_call_chain_privileges.sql',
    present: async () => {
      const result = await client.query(`
        select
          has_function_privilege('growth_migrator', 'growth.current_workspace_id()', 'EXECUTE')
          and has_function_privilege('growth_migrator', 'growth.current_app_user_id()', 'EXECUTE')
          and has_function_privilege('growth_migrator', 'growth.tenant_context_valid(uuid)', 'EXECUTE')
          as present
      `);
      return result.rows[0].present;
    },
  },
  {
    file: '049_provider_status_membership_privilege.sql',
    present: async () => {
      const result = await client.query(`
        select has_table_privilege(
          'growth_migrator',
          'growth.memberships',
          'SELECT'
        ) as present
      `);
      return result.rows[0].present;
    },
  },
  {
    file: '050_provider_helper_table_privileges.sql',
    present: async () => {
      const result = await client.query(`
        select
          has_table_privilege('growth_migrator', 'growth.memberships', 'SELECT')
          and has_table_privilege('growth_migrator', 'growth.managed_accounts', 'SELECT')
          and has_table_privilege('growth_migrator', 'growth.platform_connections', 'SELECT')
          and has_table_privilege('growth_migrator', 'growth.social_accounts', 'SELECT')
          and has_table_privilege('growth_migrator', 'growth.worker_service_principals', 'SELECT')
          as present
      `);
      return result.rows[0].present;
    },
  },
  {
    file: '051_provider_helper_jobs_privilege.sql',
    present: async () => {
      const result = await client.query(`
        select has_table_privilege(
          'growth_migrator',
          'growth.jobs',
          'SELECT'
        ) as present
      `);
      return result.rows[0].present;
    },
  },  {
    file: '052_provider_authorization_runtime_privileges.sql',
    present: async () => {
      const result = await client.query(`
        select
          has_table_privilege('growth_migrator', 'growth.users', 'SELECT')
          and has_table_privilege('growth_migrator', 'growth.workspaces', 'SELECT')
          and has_table_privilege('growth_migrator', 'growth.provider_credentials', 'INSERT')
          and has_table_privilege('growth_migrator', 'growth.platform_connections', 'INSERT')
          and has_table_privilege('growth_migrator', 'growth.platform_connections', 'UPDATE')
          and has_table_privilege('growth_migrator', 'growth.social_accounts', 'INSERT')
          and has_table_privilege('growth_migrator', 'growth.social_accounts', 'UPDATE')
          and has_function_privilege('app_runtime', 'growth.instagram_begin_authorization(uuid,text[])', 'EXECUTE')
          and has_function_privilege('app_runtime', 'growth.youtube_begin_authorization(uuid,text[])', 'EXECUTE')
          as present
      `);
      return result.rows[0].present;
    },
  },
];

try {
  await client.connect();
  const server = await client.query(
    'select current_database() as database, current_user as user',
  );
  console.log('Production migration target:', server.rows[0]);

  for (const step of steps) {
    if (await step.present()) {
      console.log(`Skipped migration (already present): ${step.file}`);
      continue;
    }

    const filePath = path.join(migrationsDir, step.file);
    const sql = normalizeSqlForPgDriver(
      await fs.readFile(filePath, 'utf8'),
      filePath,
    );
    await client.query(sql);
    console.log(`Applied migration: ${step.file}`);
  }

  if (await tableExists('growth.identity_account_cleanup_040')) {
    const cleanupResult = await client.query(
      'select action, blocking_reference_count from growth.identity_account_cleanup_040 limit 1',
    );
    console.log('Identity cleanup result:', cleanupResult.rows[0] ?? { action: 'missing' });
  }

  if (await tableExists('growth.identity_signup_smoke_cleanup_044')) {
    const smokeCleanupResult = await client.query(
      'select action, blocking_reference_count from growth.identity_signup_smoke_cleanup_044 limit 1',
    );
    console.log('Signup smoke cleanup result:', smokeCleanupResult.rows[0] ?? { action: 'missing' });
  }

  console.log('Production migration reconciliation complete');
} finally {
  await client.end();
}
