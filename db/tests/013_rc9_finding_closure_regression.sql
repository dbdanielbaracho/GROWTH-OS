-- Growth OS RC9 — RC9-FINDING-001/003 closure regression, executed against
-- fixtures from db/provisioning/test/03_test_fixtures.sql.
--
-- legit_owner = a0000000-...-0001 (own_ws + victim_ws owner)
-- attacker    = a0000000-...-0002 (zero memberships anywhere, in base fixtures)
-- own_ws      = b0000000-...-0001
-- victim_ws   = b0000000-...-0002

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- ============================================================
-- RC9-FINDING-001 exploit scenario: must now return zero rows.
-- ============================================================
DO $$
DECLARE
  leaked_rows int;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000002', true);
  SELECT count(*) INTO leaked_rows FROM growth.memberships
   WHERE workspace_id = 'b0000000-0000-4000-8000-000000000002'::uuid;
  RESET ROLE;

  IF leaked_rows <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL: RC9-FINDING-001 exploit still works — % row(s) leaked', leaked_rows;
  END IF;
  RAISE NOTICE 'PASS: RC9-FINDING-001 CLOSED — zero-membership attacker sees zero membership rows in an unrelated workspace';
END $$;

-- ============================================================
-- RC9-FINDING-003 exploit scenario: must now return zero rows.
-- ============================================================
DO $$
DECLARE
  leaked_rows int;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000002', true);
  SELECT count(*) INTO leaked_rows FROM growth.workspaces
   WHERE id = 'b0000000-0000-4000-8000-000000000002'::uuid;
  RESET ROLE;

  IF leaked_rows <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL: RC9-FINDING-003 exploit still works — % row(s) leaked', leaked_rows;
  END IF;
  RAISE NOTICE 'PASS: RC9-FINDING-003 CLOSED — zero-membership attacker sees zero workspace metadata rows';
END $$;

-- ============================================================
-- No-recursion regression: legitimate same-tenant access must not
-- stack-overflow (this is the exact failure mode of the rejected Option A).
-- ============================================================
DO $$
DECLARE
  rows_seen int;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  SELECT count(*) INTO rows_seen FROM growth.memberships;
  RESET ROLE;

  IF rows_seen < 1 THEN
    RAISE EXCEPTION 'TEST FAIL: legitimate same-tenant access returned no rows (expected at least the caller''s own row)';
  END IF;
  RAISE NOTICE 'PASS: legitimate same-tenant access works with no recursion (% rows visible)', rows_seen;
END $$;

-- ============================================================
-- Oracle-resistance regression: the function parameter alone must not
-- determine authorization independent of app.workspace_id.
-- ============================================================
DO $$
DECLARE
  probe boolean;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true); -- legit_owner, HAS membership in victim_ws
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true); -- but context is own_ws
  SELECT growth.membership_row_visible('b0000000-0000-4000-8000-000000000002'::uuid) INTO probe;
  RESET ROLE;

  IF probe THEN
    RAISE EXCEPTION 'TEST FAIL: membership_row_visible returned true for a workspace_id parameter that does not match app.workspace_id — the parameter alone determined authorization';
  END IF;
  RAISE NOTICE 'PASS: function parameter alone cannot be used as an authorization oracle (probe against victim_ws while context is own_ws correctly returned false, even though the caller genuinely has membership in victim_ws)';
END $$;

-- ============================================================
-- Test B (mandatory): nonexistent workspace.
-- ============================================================
DO $$
DECLARE
  ghost_ws uuid := 'ffffffff-ffff-4fff-8fff-ffffffffffff';
  confirmed_absent int;
  fn_result boolean;
  ws_rows int;
  mem_rows int;
BEGIN
  SELECT count(*) INTO confirmed_absent FROM growth.workspaces WHERE id = ghost_ws;
  IF confirmed_absent <> 0 THEN
    RAISE EXCEPTION 'TEST SETUP FAIL: ghost_ws unexpectedly exists';
  END IF;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', ghost_ws::text, true);
  SELECT growth.workspace_row_visible(ghost_ws) INTO fn_result;
  SELECT count(*) INTO ws_rows FROM growth.workspaces WHERE id = ghost_ws;
  SELECT count(*) INTO mem_rows FROM growth.memberships WHERE workspace_id = ghost_ws;
  RESET ROLE;

  IF fn_result IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'TEST FAIL (B): workspace_row_visible returned % for a nonexistent workspace, expected false', fn_result;
  END IF;
  IF ws_rows <> 0 OR mem_rows <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (B): nonexistent workspace leaked rows (workspaces=%, memberships=%)', ws_rows, mem_rows;
  END IF;
  RAISE NOTICE 'PASS (B): nonexistent workspace — function returns false, zero rows, no error, no leak';
END $$;

\echo 'PASS: RC9-FINDING-001/003 closure regression, oracle resistance, no-recursion, and Test B all verified'
