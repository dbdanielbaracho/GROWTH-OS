-- Growth OS — reconcile table privileges required by provider status helpers.
-- tenant_context_valid() is a SECURITY DEFINER function owned by
-- growth_migrator. Its worker-safe branch reads worker_service_principals,
-- while the user-session branch reads memberships. Reconcile both boundaries
-- explicitly so production drift cannot turn a valid session into HTTP 403.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_migrator') THEN
    RAISE EXCEPTION '050 requires growth_migrator role';
  END IF;
END $$;

GRANT USAGE ON SCHEMA growth TO growth_migrator;

GRANT SELECT ON
  growth.memberships,
  growth.managed_accounts,
  growth.platform_connections,
  growth.social_accounts,
  growth.worker_service_principals
TO growth_migrator;

DO $$
BEGIN
  IF NOT has_table_privilege('growth_migrator', 'growth.memberships', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.managed_accounts', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.platform_connections', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.social_accounts', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.worker_service_principals', 'SELECT')
  THEN
    RAISE EXCEPTION '050 provider helper table privilege reconciliation failed';
  END IF;
END $$;

COMMIT;
