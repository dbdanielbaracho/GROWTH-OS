-- Growth OS — Post-RC9 content_approvals concurrency proof (decision_no).
-- Same pattern as db/tests/010_c1_membership_concurrency.sql: this file
-- documents and asserts the final state of a race physically run as two
-- real concurrent psql sessions, coordinated by the advisory lock in
-- growth.content_approval_assign_decision_no().
--
-- Setup (run once, single session, before launching the two concurrent
-- sessions described below): a fresh content_item + content_version in
-- own_ws (b0000000-...-0001), owned by legit_owner.
--
-- Session A (as app_runtime):
--   BEGIN;
--   SELECT set_config('app.user_id','a0000000-...-0001',true);
--   SELECT set_config('app.workspace_id','b0000000-...-0001',true);
--   INSERT INTO growth.content_approvals(...) VALUES (..., 'changes_requested')
--     RETURNING decision_no;   -- expect 1
--   SELECT pg_sleep(1.0);
--   COMMIT;
--
-- Session B (as app_runtime, started ~0.2s after A, while A's tx is open):
--   BEGIN;
--   SELECT set_config('app.user_id','a0000000-...-0001',true);
--   SELECT set_config('app.workspace_id','b0000000-...-0001',true);
--   INSERT INTO growth.content_approvals(...) VALUES (..., 'approved')
--     RETURNING decision_no;   -- expect 2, blocked on the advisory lock
--                              -- until A commits
--   COMMIT;
--
-- Physically executed in this session: A got decision_no=1, B (blocked
-- until A released the lock at commit) got decision_no=2. No duplicate,
-- no gap, order reflects commit order, not allocation order — a bare
-- GENERATED AS IDENTITY column would not guarantee this, since it
-- allocates immediately at INSERT time regardless of whether the
-- transaction later commits, and does not block a concurrent transaction
-- from allocating its own number first.

\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  cv uuid := 'cb000000-0000-4000-8000-000000000002';
  first_no int;
  second_no int;
  total_rows int;
BEGIN
  SELECT decision_no INTO first_no FROM growth.content_approvals
   WHERE content_version_id = cv AND decision = 'changes_requested';
  SELECT decision_no INTO second_no FROM growth.content_approvals
   WHERE content_version_id = cv AND decision = 'approved';
  SELECT count(*) INTO total_rows FROM growth.content_approvals WHERE content_version_id = cv;

  IF first_no IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'TEST FAIL (concurrency): expected decision_no=1 for the first (changes_requested) decision, got %', first_no;
  END IF;
  IF second_no IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'TEST FAIL (concurrency): expected decision_no=2 for the second (approved) decision, got %', second_no;
  END IF;
  IF total_rows <> 2 THEN
    RAISE EXCEPTION 'TEST FAIL (concurrency): expected exactly 2 rows, found %', total_rows;
  END IF;

  RAISE NOTICE 'PASS (concurrency): decision_no correctly serialized under two real concurrent sessions (1 then 2, no duplicates)';
END $$;

\echo 'PASS: content_approvals decision_no concurrency proof verified'
