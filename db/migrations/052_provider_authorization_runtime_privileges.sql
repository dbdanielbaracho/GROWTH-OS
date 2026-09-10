-- Growth OS — reconcile provider authorization/callback runtime privileges.
-- The status helpers use read-only paths. OAuth authorization additionally
-- writes platform_connections, social_accounts and provider_credentials, while
-- the credential trigger validates the active user/workspace as growth_migrator.
-- Reconcile the complete narrow helper boundary instead of relying on 045's
-- historical marker.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_migrator') THEN
    RAISE EXCEPTION '052 requires app_runtime and growth_migrator roles';
  END IF;
END $$;

GRANT USAGE ON SCHEMA growth TO growth_migrator;

GRANT SELECT ON
  growth.users,
  growth.workspaces,
  growth.memberships,
  growth.managed_accounts,
  growth.platform_connections,
  growth.social_accounts,
  growth.worker_service_principals,
  growth.jobs
TO growth_migrator;

GRANT SELECT, INSERT, UPDATE, DELETE ON
  growth.provider_credentials
TO growth_migrator;

GRANT INSERT, UPDATE ON
  growth.platform_connections,
  growth.social_accounts
TO growth_migrator;

GRANT EXECUTE ON FUNCTION growth.current_workspace_id() TO growth_migrator;
GRANT EXECUTE ON FUNCTION growth.current_app_user_id() TO growth_migrator;
GRANT EXECUTE ON FUNCTION growth.tenant_context_valid(uuid) TO growth_migrator;

GRANT EXECUTE ON FUNCTION growth.instagram_begin_authorization(uuid,text[]) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.instagram_complete_authorization(
  uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[]
) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.youtube_begin_authorization(uuid,text[]) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.youtube_complete_authorization(
  uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[]
) TO app_runtime;

DO $$
BEGIN
  IF NOT has_table_privilege('growth_migrator', 'growth.users', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.workspaces', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.provider_credentials', 'INSERT')
     OR NOT has_table_privilege('growth_migrator', 'growth.platform_connections', 'INSERT')
     OR NOT has_table_privilege('growth_migrator', 'growth.platform_connections', 'UPDATE')
     OR NOT has_table_privilege('growth_migrator', 'growth.social_accounts', 'INSERT')
     OR NOT has_table_privilege('growth_migrator', 'growth.social_accounts', 'UPDATE')
     OR NOT has_function_privilege(
       'app_runtime',
       'growth.instagram_begin_authorization(uuid,text[])',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'app_runtime',
       'growth.instagram_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[])',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'app_runtime',
       'growth.youtube_begin_authorization(uuid,text[])',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'app_runtime',
       'growth.youtube_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[])',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION '052 provider authorization privilege reconciliation failed';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.managed_accounts', 'SELECT')
     OR has_table_privilege('app_runtime', 'growth.platform_connections', 'SELECT')
     OR has_table_privilege('app_runtime', 'growth.social_accounts', 'SELECT')
     OR has_table_privilege('app_runtime', 'growth.provider_credentials', 'SELECT')
  THEN
    RAISE EXCEPTION '052 widened app_runtime provider table boundary';
  END IF;
END $$;

COMMIT;
