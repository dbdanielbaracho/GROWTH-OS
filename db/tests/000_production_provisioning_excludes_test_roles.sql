-- Growth OS RC9 — must run against a database that has ONLY applied
-- db/provisioning/production/*.sql (never db/provisioning/test/*.sql).
-- Proves the test-only harness role never leaks into the production
-- provisioning path.

\set ON_ERROR_STOP on

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_test_harness') THEN
    RAISE EXCEPTION 'TEST FAIL: growth_test_harness exists in a database provisioned only from production/ scripts';
  END IF;
END $$;

\echo 'PASS: production provisioning contains no test-only role'
