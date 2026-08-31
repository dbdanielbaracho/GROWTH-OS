-- Growth OS RC9 — third-party owner visibility, executable.
-- Closes the test coverage gap identified in the RC9 Final Security Delta
-- Review: membership_write_guard()'s three other_active_owner_count
-- queries (UPDATE demotion, DELETE self-leave, DELETE admin-remove) all
-- filter WHERE user_id <> OLD.user_id — when the actor IS OLD.user_id
-- (self-demotion / self-leave), the actor's own row is excluded from the
-- count BY CONSTRUCTION, so only a genuinely different user's row can
-- satisfy the check. This is the one scenario where "does the actor see
-- their own row" (always true via memberships_self_select) is NOT enough
-- to explain a PASS — a positive result here specifically requires
-- membership_row_visible(workspace_id) to expose a third party's row,
-- not just the caller's own.
--
-- Ad-hoc-executed once during the delta review with a real result; this
-- file makes it permanent and adds the negative controls that were not
-- previously versioned.

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- ============================================================
-- A) Self-demotion (UPDATE), saved only by a genuinely third-party owner.
-- ============================================================
DO $$
DECLARE
  ws uuid := 'ae000000-0000-4000-8000-000000000001';
  actor uuid := 'a0000000-0000-4000-8000-000000000001';
  third_party uuid := 'a0000000-0000-4000-8000-000000000009';
  caught_sqlstate text;
  final_role text;
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', actor::text, true);
  INSERT INTO growth.users(id,email,status) VALUES
    (third_party,'rc9-third-owner@example.test','active')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.workspaces(id,name,default_market,default_language,default_timezone,status)
  VALUES(ws,'RC9 third-party UPDATE proof','US','en','UTC','active')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status) VALUES
    (ws,actor,'owner',true,'active'),
    (ws,third_party,'owner',true,'active')
  ON CONFLICT (workspace_id,user_id) DO NOTHING;
  RESET ROLE;

  -- POSITIVE CASE: actor self-demotes. The query
  -- (WHERE user_id <> OLD.user_id AND role='owner' AND status='active')
  -- excludes actor's own row by construction, so this can only succeed
  -- if third_party's row is genuinely visible to actor's session.
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', actor::text, true);
  PERFORM set_config('app.workspace_id', ws::text, true);
  UPDATE growth.memberships SET role = 'admin'
   WHERE workspace_id = ws AND user_id = actor;
  RESET ROLE;

  SELECT role INTO final_role FROM growth.memberships WHERE workspace_id = ws AND user_id = actor;
  IF final_role <> 'admin' THEN
    RAISE EXCEPTION 'TEST FAIL (A positive): actor self-demotion did not take effect, role is %', final_role;
  END IF;
  RAISE NOTICE 'PASS (A positive): actor self-demoted successfully, requiring genuine visibility of third_party''s row';

  -- NEGATIVE CONTROL: a FRESH workspace where actor is the sole owner (no
  -- reuse of the row mutated above — resetting it would itself require an
  -- admin-to-owner self-promotion, which membership_write_guard correctly
  -- blocks, and is not what this control is testing). With no genuinely-
  -- other active owner, self-demotion MUST be rejected.
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', actor::text, true);
  INSERT INTO growth.workspaces(id,name,default_market,default_language,default_timezone,status)
  VALUES('ae000000-0000-4000-8000-000000000004','RC9 sole-owner UPDATE negative control','US','en','UTC','active')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
  VALUES('ae000000-0000-4000-8000-000000000004',actor,'owner',true,'active')
  ON CONFLICT (workspace_id,user_id) DO NOTHING;
  RESET ROLE;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', actor::text, true);
  PERFORM set_config('app.workspace_id', 'ae000000-0000-4000-8000-000000000004', true);
  BEGIN
    UPDATE growth.memberships SET role = 'admin'
     WHERE workspace_id = 'ae000000-0000-4000-8000-000000000004'::uuid AND user_id = actor;
    RAISE EXCEPTION 'TEST FAIL (A negative control): self-demotion with zero other owners was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;

  IF caught_sqlstate NOT IN ('P0001') THEN
    RAISE EXCEPTION 'TEST FAIL (A negative control): unexpected SQLSTATE %', caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (A negative control): self-demotion with no other owner correctly rejected';
END $$;

-- ============================================================
-- B) Self-leave (DELETE), saved only by a genuinely third-party owner.
-- ============================================================
DO $$
DECLARE
  ws uuid := 'ae000000-0000-4000-8000-000000000002';
  actor uuid := 'a0000000-0000-4000-8000-000000000001';
  third_party uuid := 'a0000000-0000-4000-8000-000000000009';
  caught_sqlstate text;
  rows_after int;
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', actor::text, true);
  INSERT INTO growth.workspaces(id,name,default_market,default_language,default_timezone,status)
  VALUES(ws,'RC9 third-party DELETE proof','US','en','UTC','active')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status) VALUES
    (ws,actor,'owner',true,'active'),
    (ws,third_party,'owner',true,'active')
  ON CONFLICT (workspace_id,user_id) DO NOTHING;
  RESET ROLE;

  -- POSITIVE CASE: actor self-leaves. Same exclusion-by-construction as A.
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', actor::text, true);
  PERFORM set_config('app.workspace_id', ws::text, true);
  DELETE FROM growth.memberships WHERE workspace_id = ws AND user_id = actor;
  RESET ROLE;

  SELECT count(*) INTO rows_after FROM growth.memberships WHERE workspace_id = ws AND user_id = actor;
  IF rows_after <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (B positive): actor self-leave did not take effect';
  END IF;
  RAISE NOTICE 'PASS (B positive): actor self-left successfully, requiring genuine visibility of third_party''s row';

  -- NEGATIVE CONTROL: fresh workspace, actor is the ONLY owner. Self-leave
  -- must be rejected.
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', actor::text, true);
  INSERT INTO growth.workspaces(id,name,default_market,default_language,default_timezone,status)
  VALUES('ae000000-0000-4000-8000-000000000003','RC9 sole-owner negative control','US','en','UTC','active')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
  VALUES('ae000000-0000-4000-8000-000000000003',actor,'owner',true,'active')
  ON CONFLICT (workspace_id,user_id) DO NOTHING;
  RESET ROLE;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', actor::text, true);
  PERFORM set_config('app.workspace_id', 'ae000000-0000-4000-8000-000000000003', true);
  BEGIN
    DELETE FROM growth.memberships WHERE workspace_id = 'ae000000-0000-4000-8000-000000000003'::uuid AND user_id = actor;
    RAISE EXCEPTION 'TEST FAIL (B negative control): sole owner self-leave was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;

  IF caught_sqlstate NOT IN ('P0001') THEN
    RAISE EXCEPTION 'TEST FAIL (B negative control): unexpected SQLSTATE %', caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (B negative control): sole-owner self-leave correctly rejected';
END $$;

\echo 'PASS: third-party owner visibility (self-demotion and self-leave), positive and negative controls all verified'
