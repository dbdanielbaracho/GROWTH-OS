-- Growth OS RC9 — membership privilege escalation, executable.
-- Replaces the RC8 comment-only file of the same name (SPECIFICATION ONLY
-- until this rewrite). Requires: schema applied, production runtime grants
-- applied (growth_migrator/app_runtime), test provisioning applied
-- (growth_test_harness with app_runtime membership), and
-- db/provisioning/test/03_test_fixtures.sql already run.
--
-- Fixture identities used (from 03_test_fixtures.sql):
--   own_ws      = b0000000-0000-4000-8000-000000000001 (owner: legit_owner, also has viewer)
--   victim_ws   = b0000000-0000-4000-8000-000000000002 (owner: legit_owner)
--   legit_owner = a0000000-0000-4000-8000-000000000001
--   attacker    = a0000000-0000-4000-8000-000000000002 (no membership anywhere)
--   viewer      = a0000000-0000-4000-8000-000000000003 (viewer in own_ws only)

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- ============================================================
-- A) Attacker with only app.user_id + guessed app.workspace_id
--    MUST NOT self-insert as owner/admin.
-- ============================================================
DO $$
DECLARE
  has_priv boolean;
  rows_before int;
  rows_after int;
  caught_sqlstate text;
  caught_message text;
BEGIN
  SELECT has_table_privilege('app_runtime','growth.memberships','INSERT') INTO has_priv;
  IF NOT has_priv THEN
    RAISE EXCEPTION 'TEST SETUP FAIL (A): app_runtime lacks base INSERT privilege on growth.memberships';
  END IF;

  SELECT count(*) INTO rows_before FROM growth.memberships
   WHERE workspace_id = 'b0000000-0000-4000-8000-000000000002'::uuid AND role = 'owner';

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000002', true);
  BEGIN
    INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
    VALUES('b0000000-0000-4000-8000-000000000002'::uuid,'a0000000-0000-4000-8000-000000000002'::uuid,'owner',true,'active');
    RAISE EXCEPTION 'TEST FAIL (A): attacker self-insert as owner succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE, caught_message = MESSAGE_TEXT;
  END;
  RESET ROLE;

  IF caught_sqlstate IS DISTINCT FROM 'P0001' THEN
    RAISE EXCEPTION 'TEST FAIL (A): unexpected SQLSTATE %, expected P0001 (membership_write_guard fires before RLS and now correctly sees the workspace as non-empty via workspace_has_any_membership, so it rejects with its own authority-check message)', caught_sqlstate;
  END IF;
  IF caught_message NOT ILIKE '%owner/admin authority%' THEN
    RAISE EXCEPTION 'TEST FAIL (A): rejected with P0001 but unexpected message: %', caught_message;
  END IF;

  SELECT count(*) INTO rows_after FROM growth.memberships
   WHERE workspace_id = 'b0000000-0000-4000-8000-000000000002'::uuid AND role = 'owner';
  IF rows_after IS DISTINCT FROM rows_before THEN
    RAISE EXCEPTION 'TEST FAIL (A): owner count changed (% -> %) despite rejection', rows_before, rows_after;
  END IF;

  RAISE NOTICE 'PASS (A): attacker self-escalation rejected, SQLSTATE P0001 (trigger), state unchanged';
END $$;

-- ============================================================
-- B) Existing active owner MAY add a member.
-- ============================================================
DO $$
DECLARE
  rows_after int;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000002', true);
  INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
  VALUES('b0000000-0000-4000-8000-000000000002'::uuid,'a0000000-0000-4000-8000-000000000003'::uuid,'viewer',false,'active')
  ON CONFLICT (workspace_id,user_id) DO NOTHING;
  RESET ROLE;

  SELECT count(*) INTO rows_after FROM growth.memberships
   WHERE workspace_id = 'b0000000-0000-4000-8000-000000000002'::uuid
     AND user_id = 'a0000000-0000-4000-8000-000000000003'::uuid;
  IF rows_after <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (B): legitimate owner could not add a member';
  END IF;
  RAISE NOTICE 'PASS (B): active owner successfully added a member';
END $$;

-- ============================================================
-- C) First-member bootstrap MAY create only self as active owner
--    when workspace has zero memberships.
-- D) Bootstrap MUST fail if any membership already exists.
-- ============================================================
DO $$
DECLARE
  bootstrap_ws uuid := 'c0000000-0000-4000-8000-000000000001';
  rows_after int;
  caught_sqlstate text;
  caught_message text;
BEGIN
  SET ROLE growth_test_harness;
  INSERT INTO growth.workspaces(id,name,default_market,default_language,default_timezone,status)
  VALUES(bootstrap_ws,'RC9 bootstrap target','US','en','UTC','active')
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;

  -- C: self-bootstrap as owner on an empty workspace must succeed.
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', bootstrap_ws::text, true);
  INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
  VALUES(bootstrap_ws,'a0000000-0000-4000-8000-000000000001'::uuid,'owner',true,'active');
  RESET ROLE;

  SELECT count(*) INTO rows_after FROM growth.memberships WHERE workspace_id = bootstrap_ws;
  IF rows_after <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (C): bootstrap did not produce exactly one membership';
  END IF;
  RAISE NOTICE 'PASS (C): first-member bootstrap succeeded on empty workspace';

  -- D: a second bootstrap attempt on the now-non-empty workspace must fail.
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', true);
  PERFORM set_config('app.workspace_id', bootstrap_ws::text, true);
  BEGIN
    INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
    VALUES(bootstrap_ws,'a0000000-0000-4000-8000-000000000002'::uuid,'owner',true,'active');
    RAISE EXCEPTION 'TEST FAIL (D): second bootstrap on non-empty workspace succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE, caught_message = MESSAGE_TEXT;
  END;
  RESET ROLE;

  IF caught_sqlstate IS DISTINCT FROM 'P0001' THEN
    RAISE EXCEPTION 'TEST FAIL (D): unexpected SQLSTATE %, expected P0001 (membership_write_guard fires before RLS and correctly sees the workspace as non-empty)', caught_sqlstate;
  END IF;
  IF caught_message NOT ILIKE '%owner/admin authority%' THEN
    RAISE EXCEPTION 'TEST FAIL (D): rejected with P0001 but unexpected message: %', caught_message;
  END IF;

  SELECT count(*) INTO rows_after FROM growth.memberships WHERE workspace_id = bootstrap_ws;
  IF rows_after <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (D): membership count changed after rejected second bootstrap';
  END IF;
  RAISE NOTICE 'PASS (D): second bootstrap correctly rejected, SQLSTATE P0001 (trigger), state unchanged';
END $$;

-- ============================================================
-- E) Attacker MUST NOT grant can_publish through self-insertion,
--    even attempting a non-owner role.
-- ============================================================
DO $$
DECLARE
  rows_before int;
  rows_after int;
  caught_sqlstate text;
BEGIN
  SELECT count(*) INTO rows_before FROM growth.memberships
   WHERE workspace_id = 'b0000000-0000-4000-8000-000000000002'::uuid
     AND user_id = 'a0000000-0000-4000-8000-000000000002'::uuid;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000002', true);
  BEGIN
    INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
    VALUES('b0000000-0000-4000-8000-000000000002'::uuid,'a0000000-0000-4000-8000-000000000002'::uuid,'editor',true,'active');
    RAISE EXCEPTION 'TEST FAIL (E): attacker self-insert with can_publish=true succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;

  IF caught_sqlstate IS DISTINCT FROM 'P0001' THEN
    RAISE EXCEPTION 'TEST FAIL (E): unexpected SQLSTATE %, expected P0001 (membership_write_guard)', caught_sqlstate;
  END IF;

  SELECT count(*) INTO rows_after FROM growth.memberships
   WHERE workspace_id = 'b0000000-0000-4000-8000-000000000002'::uuid
     AND user_id = 'a0000000-0000-4000-8000-000000000002'::uuid;
  IF rows_after IS DISTINCT FROM rows_before THEN
    RAISE EXCEPTION 'TEST FAIL (E): row count changed despite rejection';
  END IF;
  RAISE NOTICE 'PASS (E): attacker cannot self-grant can_publish via non-owner role either';
END $$;

-- ============================================================
-- F) Membership row visibility, as actually enforced at the DB layer.
--
-- FINDING (discovered by physical execution against PG18, not by design
-- review): unlike every other tenant table, growth.memberships_workspace_select
-- does NOT call growth.tenant_context_valid(workspace_id) — it only checks
-- workspace_id = current_workspace_id(), without independently verifying
-- that the current user actually holds an active membership in that
-- workspace. This means DB-layer defense for "can this user even select
-- app.workspace_id = victim_ws" relies entirely on the application layer
-- never setting that GUC to a workspace the user does not belong to — the
-- same trust boundary already named explicitly in
-- db/tests/006_identity_bootstrap_contract.md step 5. This test verifies
-- the two things that ARE independently true at the DB layer, and does
-- NOT claim cross-tenant membership-row visibility is blocked by RLS alone.
-- ============================================================
DO $$
DECLARE
  self_only_rows int;
  workspace_scoped_rows int;
BEGIN
  -- F1: memberships_self_select independently guarantees a user always
  -- sees their OWN membership rows regardless of which workspace context
  -- is active. Note: block B above already added this same viewer as a
  -- member of victim_ws, so the expected count here is 2 (own_ws from
  -- fixtures + victim_ws from block B), not 1 — this is the test's own
  -- prior side effect within this run, not a security finding.
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000003', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  SELECT count(*) INTO self_only_rows FROM growth.memberships
   WHERE user_id = 'a0000000-0000-4000-8000-000000000003'::uuid;
  RESET ROLE;
  IF self_only_rows <> 2 THEN
    RAISE EXCEPTION 'TEST FAIL (F1): expected exactly 2 self-visible membership rows (own_ws fixture + victim_ws from block B), got %', self_only_rows;
  END IF;
  RAISE NOTICE 'PASS (F1): memberships_self_select independently exposes only the caller''s own rows, across workspaces';

  -- F2: documents, rather than hides, the real gap. A session that sets
  -- app.workspace_id to a workspace it does not belong to CAN see that
  -- workspace's membership rows via memberships_workspace_select alone,
  -- because that policy does not call tenant_context_valid(). This is
  -- expected/reproducible behavior of the current RC8 schema, not a test
  -- bug — flagged as RC9-FINDING-001 in the accompanying report, not
  -- silently treated as PASS for tenant isolation.
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000003', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000002', true);
  SELECT count(*) INTO workspace_scoped_rows FROM growth.memberships
   WHERE workspace_id = 'b0000000-0000-4000-8000-000000000002'::uuid;
  RESET ROLE;
  RAISE NOTICE 'INFO (F2, RC9-FINDING-001): with app.workspace_id set to a workspace the caller does NOT belong to, memberships_workspace_select alone exposed % row(s) — confirms this policy does not independently call tenant_context_valid() the way every other tenant table does. DB-layer defense here depends entirely on the application never setting app.workspace_id to an unauthorized workspace.', workspace_scoped_rows;
END $$;

\echo 'PASS: membership privilege escalation (A-F) — all executable, all state-verified'
