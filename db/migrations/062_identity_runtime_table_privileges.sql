-- Growth OS — reconcile the canonical identity/workspace runtime table boundary.
-- Fresh databases built from ordered migrations must not depend on a separate
-- historical provisioning pass for the authenticated workspace discovery path.
-- RLS + FORCE RLS and the membership write guard remain the authorization
-- boundary; this migration only restores the reviewed production grant matrix.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime') THEN
    RAISE EXCEPTION '062 requires app_runtime role';
  END IF;
END $$;

GRANT USAGE ON SCHEMA growth TO app_runtime;
GRANT SELECT ON growth.workspaces TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON growth.memberships TO app_runtime;

GRANT EXECUTE ON FUNCTION growth.can_manage_memberships(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.can_bootstrap_first_membership(uuid,uuid,text,text)
  TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.tenant_context_valid(uuid) TO app_runtime;

DO $$
DECLARE
  insecure_table_count integer;
BEGIN
  SELECT count(*)::integer
    INTO insecure_table_count
  FROM pg_class table_row
  JOIN pg_namespace schema_row ON schema_row.oid = table_row.relnamespace
  WHERE schema_row.nspname = 'growth'
    AND table_row.relname IN ('workspaces', 'memberships')
    AND (NOT table_row.relrowsecurity OR NOT table_row.relforcerowsecurity);

  IF insecure_table_count <> 0 THEN
    RAISE EXCEPTION '062 refuses identity grants without RLS + FORCE RLS';
  END IF;

  IF NOT has_table_privilege('app_runtime', 'growth.workspaces', 'SELECT')
     OR NOT has_table_privilege('app_runtime', 'growth.memberships', 'SELECT')
     OR NOT has_table_privilege('app_runtime', 'growth.memberships', 'INSERT')
     OR NOT has_table_privilege('app_runtime', 'growth.memberships', 'UPDATE')
     OR NOT has_table_privilege('app_runtime', 'growth.memberships', 'DELETE')
     OR NOT has_function_privilege(
       'app_runtime',
       'growth.can_manage_memberships(uuid)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'app_runtime',
       'growth.can_bootstrap_first_membership(uuid,uuid,text,text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'app_runtime',
       'growth.tenant_context_valid(uuid)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION '062 identity runtime boundary reconciliation failed';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.workspaces', 'INSERT')
     OR has_table_privilege('app_runtime', 'growth.workspaces', 'UPDATE')
     OR has_table_privilege('app_runtime', 'growth.workspaces', 'DELETE')
  THEN
    RAISE EXCEPTION '062 widened the workspace table beyond SELECT';
  END IF;
END $$;

COMMIT;
