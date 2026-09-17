-- Growth OS — deferred authority projection trigger execution boundary.
-- The managed-account consistency checks are deferred constraint triggers. They
-- can therefore fire at COMMIT under app_runtime even when the write originated
-- inside a SECURITY DEFINER identity helper. Keep direct table access closed to
-- app_runtime and run only these internal checks with the migration owner.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_migrator') THEN
    RAISE EXCEPTION '061 requires growth_migrator role';
  END IF;

  IF to_regprocedure('growth.check_managed_account_projection_consistency()') IS NULL
     OR to_regprocedure('growth.check_authority_history_projection_consistency()') IS NULL
  THEN
    RAISE EXCEPTION '061 requires both authority projection trigger functions';
  END IF;
END $$;

GRANT USAGE ON SCHEMA growth TO growth_migrator;
GRANT SELECT ON
  growth.managed_accounts,
  growth.authority_history
TO growth_migrator;

ALTER FUNCTION growth.check_managed_account_projection_consistency()
  OWNER TO growth_migrator;
ALTER FUNCTION growth.check_managed_account_projection_consistency()
  SECURITY DEFINER;
ALTER FUNCTION growth.check_managed_account_projection_consistency()
  SET search_path = pg_catalog, growth;

ALTER FUNCTION growth.check_authority_history_projection_consistency()
  OWNER TO growth_migrator;
ALTER FUNCTION growth.check_authority_history_projection_consistency()
  SECURITY DEFINER;
ALTER FUNCTION growth.check_authority_history_projection_consistency()
  SET search_path = pg_catalog, growth;

REVOKE ALL ON FUNCTION growth.check_managed_account_projection_consistency()
  FROM PUBLIC, app_runtime, growth_identity_helper, growth_rls_helper, growth_worker;
REVOKE ALL ON FUNCTION growth.check_authority_history_projection_consistency()
  FROM PUBLIC, app_runtime, growth_identity_helper, growth_rls_helper, growth_worker;

DO $$
DECLARE
  invalid_count integer;
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
    RAISE EXCEPTION '061 trigger function boundary reconciliation failed for % function(s)', invalid_count;
  END IF;

  IF NOT has_table_privilege('growth_migrator', 'growth.managed_accounts', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.authority_history', 'SELECT')
  THEN
    RAISE EXCEPTION '061 migration owner lacks authority projection read privileges';
  END IF;
END $$;

COMMIT;
