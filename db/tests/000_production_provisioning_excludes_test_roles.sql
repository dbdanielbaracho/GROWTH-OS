-- Growth OS RC9 — must run against a database that has ONLY applied
-- db/provisioning/production/*.sql (never db/provisioning/test/*.sql).
-- Proves the test-only harness role never leaks into the production
-- provisioning path.

\set ON_ERROR_STOP on

SELECT count(*) AS test_role_leaked
FROM pg_roles WHERE rolname = 'growth_test_harness' \gset

\if :test_role_leaked
  \echo 'FAIL: growth_test_harness exists in a database provisioned only from production/ scripts'
  \quit 1
\endif

\echo 'PASS: production provisioning contains no test-only role'
