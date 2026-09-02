-- Growth OS security remediation — decommission legacy validation databases.
--
-- DESTRUCTIVE. Run only after Issue #18 Phase A is green and this exact file
-- has been adversarially reviewed and merged to main.
--
-- Intended cluster: legacy Railway production PostgreSQL cluster only.
-- Intended control database: postgres.
-- Allowed drop targets ONLY:
--   growth_prod_only_000
--   growth_os_test
-- Protected databases that must remain:
--   growth_os_797f0a3
--   postgres
--   railway
--
-- Safety design:
-- - hard-coded allowlist; no dynamic database name input;
-- - refuses to run unless the pre-drop non-template database set exactly
--   matches the reviewed Issue #18 inventory;
-- - refuses to run unless growth_test_harness is absent cluster-wide;
-- - refuses to run unless both targets are owned by postgres;
-- - refuses to run if either target has any active session;
-- - uses server-side RAISE EXCEPTION for every stop condition so psql exits
--   nonzero under ON_ERROR_STOP; do not replace with psql \quit N;
-- - uses DROP DATABASE without FORCE, so a connection racing the preflight
--   causes PostgreSQL to fail rather than terminate sessions implicitly;
-- - verifies each drop independently and re-proves protected databases.
--
-- This script does NOT modify roles, grants, schemas or the production database.

\set ON_ERROR_STOP on

-- All gates use server-side exceptions. PostgreSQL 18 psql treats "\quit N" as
-- an ignored extra argument and can exit 0, which is unsafe for automation.

-- Must be launched from the provider/system control DB, never from either target.
DO $$
BEGIN
  IF current_database() <> 'postgres' THEN
    RAISE EXCEPTION 'STOP: must connect to control database postgres before running this remediation';
  END IF;
END $$;

-- Exact reviewed legacy-cluster inventory. Any extra/missing non-template DB is a
-- state change and therefore a stop condition requiring a fresh review.
DO $$
DECLARE
  mismatch_count integer;
BEGIN
  WITH expected(datname) AS (
    VALUES
      ('growth_os_797f0a3'::name),
      ('growth_os_test'::name),
      ('growth_prod_only_000'::name),
      ('postgres'::name),
      ('railway'::name)
  ), actual AS (
    SELECT datname
    FROM pg_database
    WHERE NOT datistemplate
  ), mismatch AS (
    (SELECT datname FROM expected EXCEPT SELECT datname FROM actual)
    UNION ALL
    (SELECT datname FROM actual EXCEPT SELECT datname FROM expected)
  )
  SELECT count(*) INTO mismatch_count FROM mismatch;

  IF mismatch_count <> 0 THEN
    RAISE EXCEPTION 'STOP: non-template database inventory differs from the reviewed Issue #18 state';
  END IF;
END $$;

-- The dangerous test role must already be absent before database decommission.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_test_harness') THEN
    RAISE EXCEPTION 'STOP: growth_test_harness exists on the legacy production cluster';
  END IF;
END $$;

-- Both drop targets must still exist and retain the reviewed owner.
DO $$
DECLARE
  owned_target_count integer;
BEGIN
  SELECT count(*) INTO owned_target_count
  FROM pg_database
  WHERE datname IN ('growth_os_test', 'growth_prod_only_000')
    AND pg_get_userbyid(datdba) = 'postgres';

  IF owned_target_count <> 2 THEN
    RAISE EXCEPTION 'STOP: target existence/ownership differs from reviewed Issue #18 evidence';
  END IF;
END $$;

-- No implicit session termination is authorized.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_stat_activity
    WHERE datname IN ('growth_os_test', 'growth_prod_only_000')
      AND pid <> pg_backend_pid()
  ) THEN
    RAISE EXCEPTION 'STOP: an active session exists on a legacy target database; do not terminate it ad hoc';
  END IF;
END $$;

\echo 'PASS preflight: exact legacy cluster, test role absent, targets idle and owned by postgres.'

-- Drop the smaller failed-isolation residue first. No FORCE.
DROP DATABASE growth_prod_only_000;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_database WHERE datname = 'growth_prod_only_000') THEN
    RAISE EXCEPTION 'STOP: growth_prod_only_000 still exists after DROP DATABASE';
  END IF;
END $$;

-- Recheck sessions immediately before the second destructive statement.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_stat_activity
    WHERE datname = 'growth_os_test'
      AND pid <> pg_backend_pid()
  ) THEN
    RAISE EXCEPTION 'STOP: a session appeared on growth_os_test after the first drop; do not use FORCE';
  END IF;
END $$;

DROP DATABASE growth_os_test;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_database WHERE datname = 'growth_os_test') THEN
    RAISE EXCEPTION 'STOP: growth_os_test still exists after DROP DATABASE';
  END IF;
END $$;

-- Final database-set proof: only protected production/provider DBs may remain.
DO $$
DECLARE
  mismatch_count integer;
BEGIN
  WITH expected(datname) AS (
    VALUES
      ('growth_os_797f0a3'::name),
      ('postgres'::name),
      ('railway'::name)
  ), actual AS (
    SELECT datname
    FROM pg_database
    WHERE NOT datistemplate
  ), mismatch AS (
    (SELECT datname FROM expected EXCEPT SELECT datname FROM actual)
    UNION ALL
    (SELECT datname FROM actual EXCEPT SELECT datname FROM expected)
  )
  SELECT count(*) INTO mismatch_count FROM mismatch;

  IF mismatch_count <> 0 THEN
    RAISE EXCEPTION 'STOP: final non-template database inventory is not the expected protected set';
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_test_harness') THEN
    RAISE EXCEPTION 'STOP: unexpected test-role state after database decommission';
  END IF;
END $$;

\echo 'PASS: legacy validation databases removed; production/provider databases preserved.'
