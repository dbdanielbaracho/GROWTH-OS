-- Growth OS — provider helper table privilege regression gate.
-- Proves the production privilege contract and executes both status helpers
-- through app_runtime with an authenticated tenant context.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT has_table_privilege('growth_migrator', 'growth.memberships', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.managed_accounts', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.platform_connections', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.social_accounts', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.worker_service_principals', 'SELECT')
  THEN
    RAISE EXCEPTION 'TEST FAIL: provider helper table privileges are incomplete';
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
  'c0000000-0000-4000-8000-000000000021',
  'b0000000-0000-4000-8000-000000000001',
  'direct',
  'contractually_granted',
  'private_only',
  'provider-status-helper-table-test-v1'
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
  'c0000000-0000-4000-8000-000000000022',
  'b0000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000021',
  'direct',
  'contractually_granted',
  'private_only',
  'provider-status-helper-table-test-v1',
  now()
);

SELECT set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', false);
SELECT set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', false);

SET ROLE app_runtime;

SELECT count(*) >= 0 AS instagram_status_executes
FROM growth.instagram_integration_status();

SELECT count(*) >= 0 AS youtube_status_executes
FROM growth.youtube_integration_status();

RESET ROLE;
ROLLBACK;

\echo 'PASS: provider helper table privileges are reconciled and status helpers execute'
