-- Growth OS security remediation — final removal of legacy test role.
-- Run ONLY on the legacy production PostgreSQL cluster after:
--   1) Issue #15 containment is green;
--   2) Issue #14 validation cluster is independently green;
--   3) 2026-09-02_cleanup_growth_test_harness_database.sql has been run in
--      every non-template database with role dependencies on this cluster.
--
-- This script is fail-closed: any remaining role membership or shared
-- dependency aborts the DROP ROLE.

\set ON_ERROR_STOP on

DO $$
DECLARE
  harness_oid oid;
  dependency_count integer;
BEGIN
  SELECT oid INTO harness_oid
  FROM pg_roles
  WHERE rolname = 'growth_test_harness';

  IF harness_oid IS NULL THEN
    RAISE NOTICE 'growth_test_harness already absent; nothing to drop';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE oid = harness_oid
      AND (rolcanlogin OR rolbypassrls OR rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication)
  ) THEN
    RAISE EXCEPTION 'STOP: growth_test_harness is not fully neutralized';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_auth_members am
    WHERE am.member = harness_oid OR am.roleid = harness_oid
  ) THEN
    RAISE EXCEPTION 'STOP: growth_test_harness still participates in role memberships';
  END IF;

  SELECT count(*) INTO dependency_count
  FROM pg_shdepend
  WHERE refclassid = 'pg_authid'::regclass
    AND refobjid = harness_oid;

  IF dependency_count <> 0 THEN
    RAISE EXCEPTION 'STOP: % shared dependency row(s) remain for growth_test_harness; clean every affected database first', dependency_count;
  END IF;

  RAISE NOTICE 'PASS preflight: no memberships or shared dependencies remain';
END $$;

DROP ROLE IF EXISTS growth_test_harness;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_test_harness') THEN
    RAISE EXCEPTION 'TEST FAIL: growth_test_harness still exists after DROP ROLE';
  END IF;
  RAISE NOTICE 'PASS: growth_test_harness is absent from the legacy production cluster';
END $$;
