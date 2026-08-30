-- Growth OS RC9 — TEST-ONLY provisioning.
-- growth_test_harness must NEVER appear in db/provisioning/production/.
-- It exists solely to seed adversarial fixtures across arbitrary tenants
-- before switching into app_runtime's restricted context via SET ROLE.
--
-- Run this ONLY against disposable test/CI environments.

\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_test_harness') THEN
    CREATE ROLE growth_test_harness LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS;
  END IF;
END $$;

-- BYPASSRLS only bypasses row-level security POLICIES; it does not grant
-- the underlying table-level privilege, which PostgreSQL still checks as a
-- separate layer. The harness needs broad table access across growth.* to
-- seed cross-tenant fixtures for adversarial tests. Test-only; never
-- appears in production provisioning.
GRANT USAGE ON SCHEMA growth TO growth_test_harness;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA growth TO growth_test_harness;
