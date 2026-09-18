-- Growth OS — reconcile experiment helper owner privileges.
-- Forward-only migration 066.
--
-- The route-facing experiment helpers are SECURITY DEFINER functions owned by
-- growth_migrator. Production retained the function EXECUTE boundary for
-- app_runtime, but the owner did not have the table privileges required by the
-- helper body. That made GET /v1/experiments fail with SQLSTATE 42501 while
-- preserving a superficially correct function grant matrix.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_migrator') THEN
    RAISE EXCEPTION '066 requires growth_migrator role';
  END IF;
END $$;

GRANT SELECT ON growth.opportunities TO growth_migrator;
GRANT SELECT ON growth.opportunity_evidence TO growth_migrator;
GRANT SELECT, INSERT ON growth.hypotheses TO growth_migrator;
GRANT SELECT, INSERT, UPDATE ON growth.experiments TO growth_migrator;

DO $$
BEGIN
  IF NOT has_table_privilege('growth_migrator', 'growth.opportunities', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.opportunity_evidence', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.hypotheses', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.hypotheses', 'INSERT')
     OR NOT has_table_privilege('growth_migrator', 'growth.experiments', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.experiments', 'INSERT')
     OR NOT has_table_privilege('growth_migrator', 'growth.experiments', 'UPDATE')
  THEN
    RAISE EXCEPTION '066 experiment helper owner privilege reconciliation failed';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.hypotheses', 'INSERT')
     OR has_table_privilege('app_runtime', 'growth.hypotheses', 'UPDATE')
     OR has_table_privilege('app_runtime', 'growth.hypotheses', 'DELETE')
     OR has_table_privilege('app_runtime', 'growth.experiments', 'INSERT')
     OR has_table_privilege('app_runtime', 'growth.experiments', 'UPDATE')
     OR has_table_privilege('app_runtime', 'growth.experiments', 'DELETE')
  THEN
    RAISE EXCEPTION '066 widened direct experiment writes for app_runtime';
  END IF;
END $$;

COMMIT;
