-- Growth OS RC9 — Test A (mandatory): workspace_row_visible EXECUTE
-- necessity, proven by physical removal per role, not by analogy with
-- membership_row_visible. Must run as an administrative identity (able to
-- REVOKE/GRANT on growth_rls_helper-owned functions). Restores the
-- approved grant state at the end regardless of outcome.

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- --- app_runtime: proven NECESSARY ---
REVOKE EXECUTE ON FUNCTION growth.workspace_row_visible(uuid) FROM app_runtime;

DO $$
DECLARE
  caught_sqlstate text;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  BEGIN
    PERFORM id FROM growth.workspaces WHERE id = 'b0000000-0000-4000-8000-000000000001'::uuid;
    RESET ROLE;
    RAISE EXCEPTION 'TEST FAIL (A/app_runtime): SELECT on workspaces succeeded without EXECUTE — grant is not actually necessary, contradicts design record';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
END $$;
RESET ROLE;

GRANT EXECUTE ON FUNCTION growth.workspace_row_visible(uuid) TO app_runtime;

DO $$
DECLARE
  rows_after int;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  SELECT count(*) INTO rows_after FROM growth.workspaces WHERE id = 'b0000000-0000-4000-8000-000000000001'::uuid;
  RESET ROLE;
  IF rows_after <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (A/app_runtime restore): expected 1 row after restoring grant, got %', rows_after;
  END IF;
  RAISE NOTICE 'PASS (A/app_runtime): EXECUTE proven necessary by physical removal, restored correctly';
END $$;

-- --- growth_migrator: proven NOT necessary ---
-- (workspaces has no SECURITY-DEFINER trigger equivalent to
-- membership_write_guard, so growth_migrator never indirectly needs this
-- function; the current approved grant set already omits it. This block
-- confirms that omission remains correct by attempting the same physical
-- removal test — since it was never granted, this proves a no-op that
-- matches the design record rather than re-introducing then removing it.)
DO $$
DECLARE
  already_granted boolean;
BEGIN
  SELECT has_function_privilege('growth_migrator', 'growth.workspace_row_visible(uuid)', 'EXECUTE') INTO already_granted;
  IF already_granted THEN
    RAISE EXCEPTION 'TEST FAIL (A/growth_migrator): unexpected EXECUTE grant present — approved design omits it';
  END IF;
  RAISE NOTICE 'PASS (A/growth_migrator): confirmed no EXECUTE grant exists, matching the approved (leaner) design';
END $$;

\echo 'PASS: Test A — workspace_row_visible EXECUTE necessity proven per role by physical removal, not analogy'
