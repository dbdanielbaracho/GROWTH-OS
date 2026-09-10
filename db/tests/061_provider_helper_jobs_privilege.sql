-- Growth OS — provider helper jobs privilege regression gate.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT has_table_privilege('growth_migrator', 'growth.jobs', 'SELECT') THEN
    RAISE EXCEPTION 'TEST FAIL: growth_migrator lacks jobs SELECT';
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
  'c0000000-0000-4000-8000-000000000031',
  'b0000000-0000-4000-8000-000000000001',
  'direct',
  'contractually_granted',
  'private_only',
  'provider-status-jobs-test-v1'
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
  'c0000000-0000-4000-8000-000000000032',
  'b0000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000031',
  'direct',
  'contractually_granted',
  'private_only',
  'provider-status-jobs-test-v1',
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

\echo 'PASS: provider status helpers execute with the complete tenant-context table boundary'
