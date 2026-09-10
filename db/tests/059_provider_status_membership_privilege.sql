-- Growth OS — provider status membership privilege regression gate.
-- Reproduces the production failure boundary: the status helpers must be
-- executable through app_runtime while growth_migrator can validate
-- memberships. The existing app_runtime membership grant is identity
-- functionality and is not changed by this provider migration.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT has_table_privilege(
    'growth_migrator',
    'growth.memberships',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'TEST FAIL: growth_migrator lacks memberships SELECT';
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
  'c0000000-0000-4000-8000-000000000011',
  'b0000000-0000-4000-8000-000000000001',
  'direct',
  'contractually_granted',
  'private_only',
  'provider-status-membership-test-v1'
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
  'c0000000-0000-4000-8000-000000000012',
  'b0000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000011',
  'direct',
  'contractually_granted',
  'private_only',
  'provider-status-membership-test-v1',
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

\echo 'PASS: provider status helpers validate membership through the protected role'
