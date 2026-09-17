-- Growth OS — deferred authority projection trigger privilege gate.
-- Reproduces workspace creation through app_runtime and forces both deferred
-- consistency triggers before rollback. No direct authority-history access is
-- granted to the application role.

\set ON_ERROR_STOP on

BEGIN;
SET search_path = growth, public;

DO $$
DECLARE
  invalid_count integer;
  public_execute_count integer;
BEGIN
  SELECT count(*)::integer
    INTO invalid_count
  FROM (
    VALUES
      ('growth.check_managed_account_projection_consistency()'::regprocedure),
      ('growth.check_authority_history_projection_consistency()'::regprocedure)
  ) AS expected(function_oid)
  JOIN pg_proc function_row ON function_row.oid = expected.function_oid
  WHERE NOT function_row.prosecdef
     OR pg_get_userbyid(function_row.proowner) <> 'growth_migrator'
     OR function_row.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, growth']::text[];

  IF invalid_count <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL: authority projection trigger boundary is invalid for % function(s)', invalid_count;
  END IF;

  SELECT count(*)::integer
    INTO public_execute_count
  FROM (
    VALUES
      ('growth.check_managed_account_projection_consistency()'::regprocedure),
      ('growth.check_authority_history_projection_consistency()'::regprocedure)
  ) AS expected(function_oid)
  JOIN pg_proc function_row ON function_row.oid = expected.function_oid
  CROSS JOIN LATERAL aclexplode(
    COALESCE(function_row.proacl, acldefault('f', function_row.proowner))
  ) AS privilege_row
  WHERE privilege_row.grantee = 0
    AND privilege_row.privilege_type = 'EXECUTE';

  IF public_execute_count <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL: authority projection triggers expose PUBLIC EXECUTE';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.authority_history', 'SELECT') THEN
    RAISE EXCEPTION 'TEST FAIL: app_runtime must not read authority_history directly';
  END IF;

  IF NOT has_table_privilege('growth_migrator', 'growth.managed_accounts', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.authority_history', 'SELECT')
  THEN
    RAISE EXCEPTION 'TEST FAIL: trigger owner lacks required projection reads';
  END IF;
END $$;

INSERT INTO growth.users(
  id,
  email,
  status,
  email_verified_at
)
VALUES (
  'a0000000-0000-4000-8000-000000000063',
  'authority-trigger-runtime@example.test',
  'active',
  now()
)
ON CONFLICT (id) DO UPDATE
SET status = 'active',
    email_verified_at = now();

SELECT set_config(
  'app.user_id',
  'a0000000-0000-4000-8000-000000000063',
  true
);

SET ROLE app_runtime;

SELECT growth.identity_create_workspace(
  'Authority Trigger Runtime Gate',
  'US',
  'en',
  'UTC'
) AS workspace_id
\gset

SET CONSTRAINTS ALL IMMEDIATE;

RESET ROLE;

SELECT set_config('test.workspace_id', :'workspace_id', true);

DO $$
DECLARE
  managed_count integer;
  authority_count integer;
BEGIN
  SELECT count(*)::integer
    INTO managed_count
  FROM growth.managed_accounts
  WHERE workspace_id = current_setting('test.workspace_id')::uuid;

  SELECT count(*)::integer
    INTO authority_count
  FROM growth.authority_history
  WHERE workspace_id = current_setting('test.workspace_id')::uuid
    AND effective_to IS NULL;

  IF managed_count <> 1 OR authority_count <> 1 THEN
    RAISE EXCEPTION
      'TEST FAIL: workspace onboarding projection is incomplete (managed %, authority %)',
      managed_count,
      authority_count;
  END IF;
END $$;

ROLLBACK;

\echo 'PASS: deferred authority projection triggers execute through the internal definer boundary'
