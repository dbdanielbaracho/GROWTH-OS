-- Growth OS — reconcile least-privilege table access required by the
-- SECURITY DEFINER publication reconciliation helper in production.
--
-- Production bootstrap may leave canonical tables owned by the database owner
-- while growth.record_publication_reconciliation(...) is owned by
-- growth_migrator. The helper performs SELECT ... FOR UPDATE and UPDATE on
-- publication_intents and SELECT ... FOR UPDATE / INSERT on
-- publication_reconciliation_attempts. Grant only those owner privileges;
-- app_runtime continues to use the function boundary and receives no direct
-- table access here.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_migrator') THEN
    RAISE EXCEPTION '060 requires growth_migrator role';
  END IF;
END $$;

GRANT USAGE ON SCHEMA growth TO growth_migrator;

GRANT SELECT, UPDATE ON
  growth.publication_intents
TO growth_migrator;

GRANT SELECT, INSERT, UPDATE ON
  growth.publication_reconciliation_attempts
TO growth_migrator;

DO $$
BEGIN
  IF NOT has_table_privilege('growth_migrator', 'growth.publication_intents', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.publication_intents', 'UPDATE')
     OR NOT has_table_privilege('growth_migrator', 'growth.publication_reconciliation_attempts', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.publication_reconciliation_attempts', 'INSERT')
     OR NOT has_table_privilege('growth_migrator', 'growth.publication_reconciliation_attempts', 'UPDATE')
  THEN
    RAISE EXCEPTION '060 publication reconciliation privilege reconciliation failed';
  END IF;
END $$;

COMMIT;
