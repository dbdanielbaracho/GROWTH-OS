-- Growth OS RC9 — 007_jobs_concurrency_contract.md, items 1-3.
-- Item 4 (app_runtime has zero privilege on growth.jobs) is already
-- physically proven by db/tests/002_runtime_role_gate.sql — not repeated
-- here. Item 5 (worker role claiming cross-tenant jobs) is NOT EXECUTED:
-- the approved RC9 role model (growth_migrator, app_runtime,
-- growth_test_harness) does not include a worker role — out of scope for
-- this design, not silently assumed.
--
-- jobs has no RLS (by design, per the schema's own comment: "intentionally
-- not tenant-RLS-scoped because workers claim across tenants"), so this
-- runs as growth_test_harness with full table access, not app_runtime.

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- ============================================================
-- Item 1: two tenants inserting the same (job_type, operation_key) with
-- different workspace_id must BOTH succeed.
-- ============================================================
DO $$
BEGIN
  SET ROLE growth_test_harness;
  INSERT INTO growth.jobs(id,workspace_id,job_type,operation_key,payload,state)
  VALUES
    ('90000000-0000-4000-8000-000000000001'::uuid,'b0000000-0000-4000-8000-000000000001'::uuid,'publish_content','op-shared-key','{}'::jsonb,'queued'),
    ('90000000-0000-4000-8000-000000000002'::uuid,'b0000000-0000-4000-8000-000000000002'::uuid,'publish_content','op-shared-key','{}'::jsonb,'queued');
  RESET ROLE;
  RAISE NOTICE 'PASS (item 1): same (job_type, operation_key) across two different tenants both inserted successfully';
END $$;

-- ============================================================
-- Item 2: same tenant inserting a duplicate (workspace_id, job_type,
-- operation_key) must fail/resolve to the existing job.
-- ============================================================
DO $$
DECLARE
  caught_sqlstate text;
  rows_after int;
BEGIN
  SET ROLE growth_test_harness;
  BEGIN
    INSERT INTO growth.jobs(id,workspace_id,job_type,operation_key,payload,state)
    VALUES('90000000-0000-4000-8000-000000000003'::uuid,'b0000000-0000-4000-8000-000000000001'::uuid,'publish_content','op-shared-key','{}'::jsonb,'queued');
    RAISE EXCEPTION 'TEST FAIL (item 2): duplicate tenant-scoped operation_key was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;

  IF caught_sqlstate IS DISTINCT FROM '23505' THEN
    RAISE EXCEPTION 'TEST FAIL (item 2): unexpected SQLSTATE %, expected 23505', caught_sqlstate;
  END IF;

  SELECT count(*) INTO rows_after FROM growth.jobs
   WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001'::uuid AND operation_key = 'op-shared-key';
  IF rows_after <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (item 2): expected exactly 1 row, found %', rows_after;
  END IF;
  RAISE NOTICE 'PASS (item 2): duplicate same-tenant operation_key rejected with 23505, exactly one row exists';
END $$;

-- ============================================================
-- Item 3: two global jobs (workspace_id IS NULL) with the same
-- (job_type, operation_key) — second must fail/resolve to existing.
-- ============================================================
DO $$
DECLARE
  caught_sqlstate text;
  rows_after int;
BEGIN
  SET ROLE growth_test_harness;
  INSERT INTO growth.jobs(id,workspace_id,job_type,operation_key,payload,state)
  VALUES('90000000-0000-4000-8000-000000000004'::uuid,NULL,'nightly_reconciliation','global-op-1','{}'::jsonb,'queued');

  BEGIN
    INSERT INTO growth.jobs(id,workspace_id,job_type,operation_key,payload,state)
    VALUES('90000000-0000-4000-8000-000000000005'::uuid,NULL,'nightly_reconciliation','global-op-1','{}'::jsonb,'queued');
    RAISE EXCEPTION 'TEST FAIL (item 3): duplicate global operation_key was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;

  IF caught_sqlstate IS DISTINCT FROM '23505' THEN
    RAISE EXCEPTION 'TEST FAIL (item 3): unexpected SQLSTATE %, expected 23505', caught_sqlstate;
  END IF;

  SELECT count(*) INTO rows_after FROM growth.jobs
   WHERE workspace_id IS NULL AND job_type = 'nightly_reconciliation' AND operation_key = 'global-op-1';
  IF rows_after <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (item 3): expected exactly 1 global row, found %', rows_after;
  END IF;
  RAISE NOTICE 'PASS (item 3): duplicate global operation_key rejected with 23505, exactly one row exists';
END $$;

\echo 'PASS: jobs concurrency items 1-3 executed and verified. Item 4 already proven by 002_runtime_role_gate.sql. Item 5 (worker role) NOT EXECUTED — out of RC9 approved role-model scope.'
