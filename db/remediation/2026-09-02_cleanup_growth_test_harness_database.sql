-- Growth OS security remediation — shared-cluster test-role cleanup.
-- Run ONLY on the legacy production PostgreSQL cluster after Issue #14 proves
-- that validation has moved to a genuinely separate PostgreSQL cluster.
--
-- This script is intentionally fail-closed. It refuses to continue if the
-- test role owns any object in the current database. When ownership is zero,
-- DROP OWNED is safe to use here to revoke direct ACL/default-ACL residue in
-- this database without dropping application objects.
--
-- Run this script once in every non-template database on the legacy cluster
-- for which growth_test_harness has dependencies. Do NOT run it on the new
-- Postgres-Validation cluster.

\set ON_ERROR_STOP on

DO $$
DECLARE
  harness_oid oid;
  owned_count integer;
BEGIN
  SELECT oid INTO harness_oid
  FROM pg_roles
  WHERE rolname = 'growth_test_harness';

  IF harness_oid IS NULL THEN
    RAISE NOTICE 'growth_test_harness absent; nothing to clean in database %', current_database();
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE oid = harness_oid
      AND (rolcanlogin OR rolbypassrls OR rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication)
  ) THEN
    RAISE EXCEPTION 'STOP: growth_test_harness is not fully neutralized before cleanup';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_auth_members am
    WHERE am.member = harness_oid OR am.roleid = harness_oid
  ) THEN
    RAISE EXCEPTION 'STOP: growth_test_harness still has role memberships';
  END IF;

  SELECT count(*) INTO owned_count
  FROM pg_shdepend
  WHERE refclassid = 'pg_authid'::regclass
    AND refobjid = harness_oid
    AND dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
    AND deptype = 'o';

  IF owned_count <> 0 THEN
    RAISE EXCEPTION 'STOP: growth_test_harness owns % object(s) in database %', owned_count, current_database();
  END IF;

  RAISE NOTICE 'PASS preflight: role neutralized, no memberships, no owned objects in database %', current_database();
END $$;

-- With ownership proven zero above, this only removes privileges/default ACLs
-- attributable directly to the legacy test role in the current database.
DROP OWNED BY growth_test_harness;

DO $$
DECLARE
  harness_oid oid;
  remaining_deps integer;
BEGIN
  SELECT oid INTO harness_oid
  FROM pg_roles
  WHERE rolname = 'growth_test_harness';

  IF harness_oid IS NULL THEN
    RETURN;
  END IF;

  SELECT count(*) INTO remaining_deps
  FROM pg_shdepend
  WHERE refclassid = 'pg_authid'::regclass
    AND refobjid = harness_oid
    AND dbid = (SELECT oid FROM pg_database WHERE datname = current_database());

  IF remaining_deps <> 0 THEN
    RAISE EXCEPTION 'STOP: % role dependency row(s) remain in database % after cleanup', remaining_deps, current_database();
  END IF;

  RAISE NOTICE 'PASS: no growth_test_harness dependencies remain in database %', current_database();
END $$;
