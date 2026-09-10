-- Growth OS — provider status helper call-chain privileges.
-- The route-facing status helpers are SECURITY DEFINER functions owned by
-- growth_migrator. Their internal tenant_context_valid() call is a separate
-- function privilege check and must be granted explicitly to that owner.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_migrator') THEN
    RAISE EXCEPTION '048 requires app_runtime and growth_migrator roles';
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION growth.current_workspace_id() TO growth_migrator;
GRANT EXECUTE ON FUNCTION growth.current_app_user_id() TO growth_migrator;
GRANT EXECUTE ON FUNCTION growth.tenant_context_valid(uuid) TO growth_migrator;

DO $$
BEGIN
  IF NOT has_function_privilege(
    'growth_migrator',
    'growth.current_workspace_id()',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'growth_migrator',
    'growth.current_app_user_id()',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'growth_migrator',
    'growth.tenant_context_valid(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION '048 failed: provider status helper call chain is not executable';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.managed_accounts', 'SELECT')
     OR has_table_privilege('app_runtime', 'growth.platform_connections', 'SELECT')
     OR has_table_privilege('app_runtime', 'growth.social_accounts', 'SELECT') THEN
    RAISE EXCEPTION '048 failed: provider table boundary widened for app_runtime';
  END IF;
END $$;

COMMIT;
