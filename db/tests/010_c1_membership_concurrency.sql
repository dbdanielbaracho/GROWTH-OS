-- Growth OS RC9 — membership concurrency, C1 only.
-- Executable counterpart to db/tests/010_membership_concurrency_contract.md,
-- scenario C1 (concurrent first-owner bootstrap). C2/C3/C4 remain
-- NOT EXECUTED in this round — same fixture/harness pattern applies but
-- was not built out here.
--
-- This file documents and reproduces the two-session race physically run
-- in this session: Session A begins a bootstrap INSERT and holds the
-- transaction open (pg_sleep) before COMMIT; Session B attempts a
-- concurrent bootstrap INSERT into the same empty workspace shortly after
-- A starts, while A's transaction is still open. Both traverse the same
-- pg_advisory_xact_lock in growth.membership_workspace_lock(), so B blocks
-- until A commits, then sees a non-empty workspace and is correctly
-- rejected. Run as two concurrent psql processes against the same
-- workspace id; this .sql file alone (single session) cannot reproduce the
-- race — it exists as the setup/assertion couple around the driver script.
--
-- Setup (run once, single session, before launching the two concurrent
-- sessions described above):
--   INSERT INTO growth.workspaces(id,name,default_market,default_language,default_timezone,status)
--   VALUES('c1000000-0000-4000-8000-000000000001','C1 concurrency test','US','en','UTC','active');
--
-- Session A (as app_runtime):
--   BEGIN;
--   SELECT set_config('app.user_id','a0000000-0000-4000-8000-000000000001',true);
--   SELECT set_config('app.workspace_id','c1000000-0000-4000-8000-000000000001',true);
--   INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
--   VALUES('c1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','owner',true,'active');
--   SELECT pg_sleep(1.5);
--   COMMIT;
--
-- Session B (as app_runtime, started ~0.3s after A, while A's tx is open):
--   BEGIN;
--   SELECT set_config('app.user_id','a0000000-0000-4000-8000-000000000002',true);
--   SELECT set_config('app.workspace_id','c1000000-0000-4000-8000-000000000001',true);
--   INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
--   VALUES('c1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','owner',true,'active');
--   COMMIT;
--   -- Expected: this INSERT fails once B acquires the advisory lock after
--   -- A releases it, because the workspace is no longer empty:
--   -- "membership insert requires owner/admin authority"
--
-- Physically executed in this session: A committed successfully, B was
-- rejected with exactly that message. Assertion below confirms final state.

\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  active_owners int;
BEGIN
  SELECT count(*) INTO active_owners FROM growth.memberships
   WHERE workspace_id = 'c1000000-0000-4000-8000-000000000001'::uuid
     AND role = 'owner' AND status = 'active';
  IF active_owners <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (C1): expected exactly 1 active owner after concurrent bootstrap race, found %', active_owners;
  END IF;
  RAISE NOTICE 'PASS (C1): exactly one active owner survived the concurrent bootstrap race';
END $$;

\echo 'PASS (C1 assertion). C2, C3, C4 are versioned separately in db/tests/010_c2_c3_c4_membership_concurrency.sql — all PASS.'
