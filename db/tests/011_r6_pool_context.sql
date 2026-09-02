-- Growth OS RC9 — 011_rc8_six_fail_regressions.md, R6 only.
-- Pool partial-context safety: clearing only app.user_id while leaving
-- app.workspace_id set must deny ordinary tenant-table access, since
-- tenant_context_valid() requires current_app_user_id() IS NOT NULL.

\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  ws uuid := 'b0000000-0000-4000-8000-000000000001';
  rows_with_valid_context int;
  rows_with_user_cleared int;
  rows_after_restore int;
  rows_wrong_tenant int;
BEGIN
  -- Valid context: A's own workspace, A's own user_id. content_items
  -- fixtures already exist from the L1/006 test setup.
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', ws::text, true);
  SELECT count(*) INTO rows_with_valid_context FROM growth.content_items WHERE workspace_id = ws;
  IF rows_with_valid_context = 0 THEN
    RAISE EXCEPTION 'TEST SETUP FAIL (R6): expected at least one visible content_items row with valid context';
  END IF;
  RAISE NOTICE 'PASS (R6 baseline): % row(s) visible with valid user_id + workspace_id context', rows_with_valid_context;

  -- Clear ONLY app.user_id, leave app.workspace_id set. tenant_context_valid()
  -- requires current_app_user_id() IS NOT NULL, so this must return zero.
  PERFORM set_config('app.user_id', '', true);
  SELECT count(*) INTO rows_with_user_cleared FROM growth.content_items WHERE workspace_id = ws;
  IF rows_with_user_cleared <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (R6): content_items returned % rows with app.user_id cleared but app.workspace_id still set — partial pool context leak', rows_with_user_cleared;
  END IF;
  RAISE NOTICE 'PASS (R6 partial-context): zero rows visible with app.user_id cleared, app.workspace_id still set';

  -- Restore a valid A user: rows must reappear.
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  SELECT count(*) INTO rows_after_restore FROM growth.content_items WHERE workspace_id = ws;
  IF rows_after_restore <> rows_with_valid_context THEN
    RAISE EXCEPTION 'TEST FAIL (R6): row count after restoring user_id (%) does not match baseline (%)', rows_after_restore, rows_with_valid_context;
  END IF;
  RAISE NOTICE 'PASS (R6 restore): rows reappear correctly after restoring a valid user_id';
  RESET ROLE;

  -- A user active only in a DIFFERENT tenant cannot read A's data merely
  -- by setting app.workspace_id = A's workspace (viewer, a...003, has no
  -- membership in workspace B / victim_ws, but does have one in own_ws=ws
  -- itself — use the genuine zero-membership-anywhere attacker instead).
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', true); -- attacker: zero memberships anywhere
  PERFORM set_config('app.workspace_id', ws::text, true);
  SELECT count(*) INTO rows_wrong_tenant FROM growth.content_items WHERE workspace_id = ws;
  RESET ROLE;
  IF rows_wrong_tenant <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (R6 cross-tenant): user with no membership in this workspace saw % rows by setting app.workspace_id alone', rows_wrong_tenant;
  END IF;
  RAISE NOTICE 'PASS (R6 cross-tenant): a user with no membership in the workspace sees zero rows merely by setting app.workspace_id, for tables that call tenant_context_valid()';
END $$;

\echo 'PASS: R6 pool partial-context safety fully verified'
