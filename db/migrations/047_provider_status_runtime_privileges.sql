-- Growth OS — provider status runtime privilege reconciliation.
-- Production drift can leave SECURITY DEFINER status helpers present but
-- non-executable by app_runtime. Reconcile the narrow function boundary
-- explicitly without granting app_runtime direct table access.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_migrator') THEN
    RAISE EXCEPTION '047 requires app_runtime and growth_migrator roles';
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION growth.youtube_integration_status() TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.instagram_integration_status() TO app_runtime;

DO $$
BEGIN
  IF NOT has_function_privilege(
    'app_runtime',
    'growth.youtube_integration_status()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION '047 failed: app_runtime cannot execute youtube status helper';
  END IF;

  IF NOT has_function_privilege(
    'app_runtime',
    'growth.instagram_integration_status()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION '047 failed: app_runtime cannot execute instagram status helper';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.managed_accounts', 'SELECT')
     OR has_table_privilege('app_runtime', 'growth.platform_connections', 'SELECT')
     OR has_table_privilege('app_runtime', 'growth.social_accounts', 'SELECT') THEN
    RAISE EXCEPTION '047 failed: provider table boundary widened for app_runtime';
  END IF;
END $$;

COMMIT;
