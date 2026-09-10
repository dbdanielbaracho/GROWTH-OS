-- Growth OS — reconcile the remaining provider helper table privilege.
-- tenant_context_valid() contains both the user-session and worker-session
-- branches. PostgreSQL checks privileges for the complete function query,
-- including growth.jobs, even when the current request uses the user branch.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_migrator') THEN
    RAISE EXCEPTION '051 requires growth_migrator role';
  END IF;
END $$;

GRANT SELECT ON growth.jobs TO growth_migrator;

DO $$
BEGIN
  IF NOT has_table_privilege('growth_migrator', 'growth.jobs', 'SELECT') THEN
    RAISE EXCEPTION '051 failed: growth_migrator cannot validate worker job context';
  END IF;
END $$;

COMMIT;
