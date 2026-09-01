-- Growth OS — Creative Production TEST-ONLY fixtures.
-- Additive, never edits db/provisioning/test/03_test_fixtures.sql (RC9,
-- frozen alongside the other original test-provisioning files) — same
-- discipline already applied to db/provisioning/production/*_grants.sql,
-- each new module adds its own numbered file rather than editing an
-- earlier one.
--
-- Origin: apps/api/integration-tests/creative-production.integration.mts
-- test (3) (cross-workspace source_id rejection, a SECURITY-relevant
-- check) was silently degrading to a SKIP whenever no opportunity fixture
-- existed in the victim workspace — meaning that specific security
-- assertion could go unexercised in an entire CI run without the overall
-- suite failing. Seeding these two fixtures here, as part of standard
-- provisioning, makes that no longer possible: the check now always runs.
-- (The test itself was also hardened, in the same change, to FAIL rather
-- than SKIP if this fixture were ever absent again — this file is
-- defense-in-depth, not the only thing preventing the gap from recurring.)
--
-- Run as growth_test_harness (BYPASSRLS), after 03_test_fixtures.sql.

\set ON_ERROR_STOP on
SET search_path = growth, public;

SELECT set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', false);

INSERT INTO growth.opportunities(id, workspace_id, market, platform, status, ranking_version) VALUES
  ('f6000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', 'US', 'instagram', 'active', 'v1'),
  ('f6000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000002', 'US', 'instagram', 'active', 'v1')
ON CONFLICT (id) DO NOTHING;

\echo 'PASS: Creative Production test fixtures seeded'
