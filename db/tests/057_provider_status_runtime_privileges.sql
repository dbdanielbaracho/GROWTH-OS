-- Growth OS — provider status runtime privilege regression gate.
-- Confirms the route-facing role can execute only the protected status helpers.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT has_function_privilege(
    'app_runtime',
    'growth.youtube_integration_status()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'TEST FAIL: app_runtime lacks YouTube status EXECUTE';
  END IF;

  IF NOT has_function_privilege(
    'app_runtime',
    'growth.instagram_integration_status()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'TEST FAIL: app_runtime lacks Instagram status EXECUTE';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.managed_accounts', 'SELECT')
     OR has_table_privilege('app_runtime', 'growth.platform_connections', 'SELECT')
     OR has_table_privilege('app_runtime', 'growth.social_accounts', 'SELECT') THEN
    RAISE EXCEPTION 'TEST FAIL: app_runtime received direct provider table SELECT';
  END IF;
END $$;

ROLLBACK;

\echo 'PASS: app_runtime can execute protected provider status helpers without direct table reads'
