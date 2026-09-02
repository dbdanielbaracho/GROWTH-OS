-- Growth OS RC9 — TEST-ONLY deterministic fixtures.
-- Run as growth_test_harness (BYPASSRLS) so seeding is not itself gated
-- by the RLS policies under test. Fixed UUIDs for reproducibility across
-- runs; tests that need additional fixtures create them inline.

\set ON_ERROR_STOP on
SET search_path = growth, public;

INSERT INTO growth.users(id, email, status) VALUES
  ('a0000000-0000-4000-8000-000000000001', 'rc9-legit-owner@example.test', 'active'),
  ('a0000000-0000-4000-8000-000000000002', 'rc9-attacker@example.test', 'active'),
  ('a0000000-0000-4000-8000-000000000003', 'rc9-viewer@example.test', 'active')
ON CONFLICT (id) DO NOTHING;

INSERT INTO growth.workspaces(id, name, default_market, default_language, default_timezone, status) VALUES
  ('b0000000-0000-4000-8000-000000000001', 'RC9 own workspace', 'US', 'en', 'UTC', 'active'),
  ('b0000000-0000-4000-8000-000000000002', 'RC9 victim workspace', 'US', 'en', 'UTC', 'active')
ON CONFLICT (id) DO NOTHING;

-- memberships_write_guard requires app.user_id even for this BYPASSRLS
-- harness: BYPASSRLS only bypasses RLS *policies*, not BEFORE triggers.
-- The harness acts as its own recorded actor for fixture seeding.
SELECT set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', false);

INSERT INTO growth.memberships(workspace_id, user_id, role, can_publish, status) VALUES
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'owner', true, 'active'),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'owner', true, 'active'),
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000003', 'viewer', false, 'active')
ON CONFLICT (workspace_id, user_id) DO NOTHING;

\echo 'PASS: deterministic fixtures seeded'
