-- Growth OS — provider authorization/callback runtime gate.
-- Executes both provider write paths through app_runtime with a real tenant
-- context and rolls back all synthetic connection/credential rows.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT has_table_privilege('growth_migrator', 'growth.users', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.workspaces', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.provider_credentials', 'INSERT')
     OR NOT has_table_privilege('growth_migrator', 'growth.platform_connections', 'INSERT')
     OR NOT has_table_privilege('growth_migrator', 'growth.platform_connections', 'UPDATE')
     OR NOT has_table_privilege('growth_migrator', 'growth.social_accounts', 'INSERT')
     OR NOT has_table_privilege('growth_migrator', 'growth.social_accounts', 'UPDATE')
  THEN
    RAISE EXCEPTION 'TEST FAIL: provider authorization write privileges are incomplete';
  END IF;
END $$;

INSERT INTO growth.managed_accounts(
  id,
  workspace_id,
  owner_type,
  authority_status,
  contribution_eligibility,
  authority_clause_ref
)
VALUES (
  'c0000000-0000-4000-8000-000000000041',
  'b0000000-0000-4000-8000-000000000001',
  'direct',
  'contractually_granted',
  'private_only',
  'provider-authorization-runtime-test-v1'
);

INSERT INTO growth.authority_history(
  id,
  workspace_id,
  managed_account_id,
  owner_type,
  authority_status,
  contribution_eligibility,
  authority_clause_ref,
  effective_from
)
VALUES (
  'c0000000-0000-4000-8000-000000000042',
  'b0000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000041',
  'direct',
  'contractually_granted',
  'private_only',
  'provider-authorization-runtime-test-v1',
  now()
);

SELECT set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', false);
SELECT set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', false);

SET ROLE app_runtime;

SELECT growth.instagram_begin_authorization(
  'c0000000-0000-4000-8000-000000000041'::uuid,
  ARRAY['instagram_business_basic']::text[]
) AS connection_id
\gset instagram_

SELECT growth.youtube_begin_authorization(
  'c0000000-0000-4000-8000-000000000041'::uuid,
  ARRAY['https://www.googleapis.com/auth/youtube.readonly']::text[]
) AS connection_id
\gset youtube_

SELECT growth.instagram_complete_authorization(
  :'instagram_connection_id'::uuid,
  'provider-instagram-authorization-test-v1',
  'provider-test',
  'BUSINESS',
  NULL,
  NULL,
  decode('deadbeef', 'hex'),
  'aes-256-gcm.v1',
  'v1',
  now() + interval '1 hour',
  true,
  ARRAY['instagram_business_basic']::text[]
) AS social_account_id;

SELECT growth.youtube_complete_authorization(
  :'youtube_connection_id'::uuid,
  'provider-youtube-authorization-test-v1',
  'provider-test',
  'channel',
  NULL,
  'America/Los_Angeles',
  decode('cafebabe', 'hex'),
  'aes-256-gcm.v1',
  'v1',
  now() + interval '1 hour',
  false,
  ARRAY['https://www.googleapis.com/auth/youtube.readonly']::text[]
) AS social_account_id;

SELECT count(*) >= 0 AS instagram_status_executes
FROM growth.instagram_integration_status();

SELECT count(*) >= 0 AS youtube_status_executes
FROM growth.youtube_integration_status();

RESET ROLE;
ROLLBACK;

\echo 'PASS: Instagram and YouTube authorization/callback write paths execute through app_runtime'
