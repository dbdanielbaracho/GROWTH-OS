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
-- - uses DROP DATABASE without FORCE, so a connection racing the preflight
--   causes PostgreSQL to fail rather than terminate sessions implicitly;
-- - verifies each drop independently and re-proves protected databases.
--
-- This script does NOT modify roles, grants, schemas or the production database.

\set ON_ERROR_STOP on

-- Must be launched from the provider/system control DB, never from either target.
SELECT (current_database() = 'postgres') AS connected_to_control_db \gset
\if :connected_to_control_db
\else
  \echo 'STOP: must connect to control database postgres before running this remediation.'
  \quit 20
\endif

-- Exact reviewed legacy-cluster inventory. Any extra/missing non-template DB is a
-- state change and therefore a stop condition requiring a fresh review.
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
SELECT (count(*) = 0) AS exact_database_inventory
FROM mismatch \gset
\if :exact_database_inventory
\else
  \echo 'STOP: non-template database inventory differs from the reviewed Issue #18 state.'
  \quit 21
\endif

-- The dangerous test role must already be absent before database decommission.
SELECT (count(*) = 0) AS harness_absent
FROM pg_roles
WHERE rolname = 'growth_test_harness' \gset
\if :harness_absent
\else
  \echo 'STOP: growth_test_harness exists on the legacy production cluster.'
  \quit 22
\endif

-- Both drop targets must still exist and retain the reviewed owner.
SELECT (count(*) = 2) AS targets_owned_by_postgres
FROM pg_database
WHERE datname IN ('growth_os_test', 'growth_prod_only_000')
  AND pg_get_userbyid(datdba) = 'postgres' \gset
\if :targets_owned_by_postgres
\else
  \echo 'STOP: target existence/ownership differs from reviewed Issue #18 evidence.'
  \quit 23
\endif

-- No implicit session termination is authorized.
SELECT (count(*) = 0) AS targets_idle
FROM pg_stat_activity
WHERE datname IN ('growth_os_test', 'growth_prod_only_000')
  AND pid <> pg_backend_pid() \gset
\if :targets_idle
\else
  \echo 'STOP: an active session exists on a legacy target database. Do not terminate it ad hoc.'
  \quit 24
\endif

\echo 'PASS preflight: exact legacy cluster, test role absent, targets idle and owned by postgres.'

-- Drop the smaller failed-isolation residue first. No FORCE.
DROP DATABASE growth_prod_only_000;

SELECT (count(*) = 0) AS first_target_absent
FROM pg_database
WHERE datname = 'growth_prod_only_000' \gset
\if :first_target_absent
\else
  \echo 'STOP: growth_prod_only_000 still exists after DROP DATABASE.'
  \quit 25
\endif

-- Recheck sessions immediately before the second destructive statement.
SELECT (count(*) = 0) AS second_target_idle
FROM pg_stat_activity
WHERE datname = 'growth_os_test'
  AND pid <> pg_backend_pid() \gset
\if :second_target_idle
\else
  \echo 'STOP: a session appeared on growth_os_test after the first drop. Do not use FORCE.'
  \quit 26
\endif

DROP DATABASE growth_os_test;

SELECT (count(*) = 0) AS second_target_absent
FROM pg_database
WHERE datname = 'growth_os_test' \gset
\if :second_target_absent
\else
  \echo 'STOP: growth_os_test still exists after DROP DATABASE.'
  \quit 27
\endif

-- Final database-set proof: only protected production/provider DBs may remain.
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
SELECT (count(*) = 0) AS final_database_inventory
FROM mismatch \gset
\if :final_database_inventory
\else
  \echo 'STOP: final non-template database inventory is not the expected protected set.'
  \quit 28
\endif

SELECT (count(*) = 0) AS harness_still_absent
FROM pg_roles
WHERE rolname = 'growth_test_harness' \gset
\if :harness_still_absent
\else
  \echo 'STOP: unexpected test-role state after database decommission.'
  \quit 29
\endif

\echo 'PASS: legacy validation databases removed; production/provider databases preserved.'
