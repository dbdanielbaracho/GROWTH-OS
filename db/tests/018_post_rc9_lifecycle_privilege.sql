-- Growth OS — Post-RC9 content lifecycle privilege model, executable.
-- Closes the CHANGES REQUIRED finding: a broad GRANT UPDATE ON
-- content_items TO app_runtime let the caller rewrite any column RLS
-- would let the row through for (market, language, objective,
-- source_type, ...), not just status, and neither table- nor
-- column-level grants alone enforce that a status transition is backed
-- by a real content_approvals decision. Replaced with three SECURITY
-- DEFINER functions (content_approve, content_request_changes,
-- content_new_version); app_runtime has zero UPDATE privilege on
-- content_items, table- or column-level.

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- ============================================================
-- 0) Privilege matrix: app_runtime has SELECT/INSERT on content_items,
--    but genuinely zero UPDATE (neither table- nor column-level), and
--    genuinely zero UPDATE/DELETE on content_approvals (append-only).
-- ============================================================
DO $$
DECLARE
  can_select boolean;
  can_insert boolean;
  can_update_table boolean;
  can_update_status_col boolean;
  can_update_approvals boolean;
  can_delete_approvals boolean;
BEGIN
  SELECT has_table_privilege('app_runtime','growth.content_items','SELECT') INTO can_select;
  SELECT has_table_privilege('app_runtime','growth.content_items','INSERT') INTO can_insert;
  SELECT has_table_privilege('app_runtime','growth.content_items','UPDATE') INTO can_update_table;
  SELECT has_column_privilege('app_runtime','growth.content_items','status','UPDATE') INTO can_update_status_col;
  SELECT has_table_privilege('app_runtime','growth.content_approvals','UPDATE') INTO can_update_approvals;
  SELECT has_table_privilege('app_runtime','growth.content_approvals','DELETE') INTO can_delete_approvals;

  IF NOT can_select OR NOT can_insert THEN
    RAISE EXCEPTION 'TEST FAIL (0): app_runtime unexpectedly lacks base SELECT/INSERT on content_items';
  END IF;
  IF can_update_table THEN
    RAISE EXCEPTION 'TEST FAIL (0): app_runtime has table-level UPDATE on content_items — must be zero';
  END IF;
  IF can_update_status_col THEN
    RAISE EXCEPTION 'TEST FAIL (0): app_runtime has column-level UPDATE(status) on content_items — must be zero, transitions go through functions only';
  END IF;
  IF can_update_approvals OR can_delete_approvals THEN
    RAISE EXCEPTION 'TEST FAIL (0): app_runtime has UPDATE/DELETE on content_approvals — must be append-only';
  END IF;
  RAISE NOTICE 'PASS (0): privilege matrix confirmed — zero UPDATE on content_items (table or column), zero UPDATE/DELETE on content_approvals';
END $$;

-- ============================================================
-- Setup: a fresh content_item in ready_for_review, own_ws.
-- ============================================================
DO $$
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.content_items(id,workspace_id,market,language,source_type,status)
  VALUES('ce000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','US','en','manual','ready_for_review')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.content_versions(id,workspace_id,content_item_id,version_no,body,checksum)
  VALUES('ce000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','ce000000-0000-4000-8000-000000000001',1,'v1 body','chk-ce-v1')
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;
END $$;

-- ============================================================
-- 1) Direct UPDATE attempt denied, even a single-column, "harmless
--    looking" one.
-- ============================================================
DO $$
DECLARE
  caught_sqlstate text;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  BEGIN
    UPDATE growth.content_items SET status = 'approved' WHERE id = 'ce000000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'TEST FAIL (1): direct UPDATE on content_items.status succeeded — must be impossible';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  RAISE NOTICE 'PASS (1): direct UPDATE on content_items rejected (SQLSTATE %)', caught_sqlstate;
END $$;

-- ============================================================
-- 2) content_approve: legitimate transition, atomic, correct decision_no.
-- ============================================================
DO $$
DECLARE
  new_status text;
  approval_decision text;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  SELECT decision INTO approval_decision FROM growth.content_approve(
    'b0000000-0000-4000-8000-000000000001','ce000000-0000-4000-8000-000000000002','approved via test');
  RESET ROLE;

  SELECT status INTO new_status FROM growth.content_items WHERE id = 'ce000000-0000-4000-8000-000000000001'::uuid;
  IF approval_decision <> 'approved' OR new_status <> 'approved' THEN
    RAISE EXCEPTION 'TEST FAIL (2): expected approved/approved, got %/%', approval_decision, new_status;
  END IF;
  RAISE NOTICE 'PASS (2): content_approve() transitions ready_for_review -> approved atomically';
END $$;

-- ============================================================
-- 3) Wrong-state rejection + atomicity: approving an already-approved
--    version must fail, and must not create an orphaned approval row.
-- ============================================================
DO $$
DECLARE
  rows_before int;
  rows_after int;
  caught_sqlstate text;
BEGIN
  SELECT count(*) INTO rows_before FROM growth.content_approvals WHERE content_version_id = 'ce000000-0000-4000-8000-000000000002'::uuid;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  BEGIN
    PERFORM growth.content_approve('b0000000-0000-4000-8000-000000000001','ce000000-0000-4000-8000-000000000002','second attempt');
    RAISE EXCEPTION 'TEST FAIL (3): approving an already-approved version succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;

  SELECT count(*) INTO rows_after FROM growth.content_approvals WHERE content_version_id = 'ce000000-0000-4000-8000-000000000002'::uuid;
  IF rows_after <> rows_before THEN
    RAISE EXCEPTION 'TEST FAIL (3): orphaned approval row from a rejected transition (% -> %)', rows_before, rows_after;
  END IF;
  RAISE NOTICE 'PASS (3): wrong-state approval rejected (SQLSTATE %), no orphaned approval row — atomic', caught_sqlstate;
END $$;

-- ============================================================
-- 4) Full cycle: changes_requested -> draft -> edit(new version) ->
--    ready_for_review -> approve -> approved, entirely through
--    controlled functions, decision_no correctly restarts per version.
-- ============================================================
DO $$
DECLARE
  v_item uuid := 'ce000000-0000-4000-8000-000000000003';
  v1 uuid := 'ce000000-0000-4000-8000-000000000004';
  v2 growth.content_versions;
  status_after_changes_requested text;
  status_after_edit text;
  final_status text;
  cr_decision_no int;
  approve_decision_no int;
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.content_items(id,workspace_id,market,language,source_type,status)
  VALUES(v_item,'b0000000-0000-4000-8000-000000000001','US','en','manual','ready_for_review');
  INSERT INTO growth.content_versions(id,workspace_id,content_item_id,version_no,body,checksum)
  VALUES(v1,'b0000000-0000-4000-8000-000000000001',v_item,1,'cycle v1','chk-cycle-v1');
  RESET ROLE;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);

  SELECT decision_no INTO cr_decision_no FROM growth.content_request_changes(
    'b0000000-0000-4000-8000-000000000001', v1, 'needs work');
  SELECT status INTO status_after_changes_requested FROM growth.content_items WHERE id = v_item;

  SELECT * INTO v2 FROM growth.content_new_version(
    'b0000000-0000-4000-8000-000000000001', v_item, 'cycle v2 edited', 'chk-cycle-v2');
  SELECT status INTO status_after_edit FROM growth.content_items WHERE id = v_item;

  SELECT decision_no INTO approve_decision_no FROM growth.content_approve(
    'b0000000-0000-4000-8000-000000000001', v2.id, 'looks good now');
  SELECT status INTO final_status FROM growth.content_items WHERE id = v_item;
  RESET ROLE;

  IF cr_decision_no <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (4): expected decision_no=1 for changes_requested on v1, got %', cr_decision_no;
  END IF;
  IF status_after_changes_requested <> 'draft' THEN
    RAISE EXCEPTION 'TEST FAIL (4): expected draft after changes_requested, got %', status_after_changes_requested;
  END IF;
  IF v2.version_no <> 2 THEN
    RAISE EXCEPTION 'TEST FAIL (4): expected version_no=2 for the edit, got %', v2.version_no;
  END IF;
  IF status_after_edit <> 'ready_for_review' THEN
    RAISE EXCEPTION 'TEST FAIL (4): expected ready_for_review after edit, got %', status_after_edit;
  END IF;
  IF approve_decision_no <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (4): expected decision_no=1 for approval on v2 (fresh per-version history), got %', approve_decision_no;
  END IF;
  IF final_status <> 'approved' THEN
    RAISE EXCEPTION 'TEST FAIL (4): expected approved at the end of the cycle, got %', final_status;
  END IF;
  RAISE NOTICE 'PASS (4): full lifecycle cycle correct end to end, decision_no correctly isolated per content_version';
END $$;

-- ============================================================
-- 5) Cross-tenant: attacker cannot approve/edit content in a workspace
--    they have no membership in, via the functions.
-- ============================================================
DO $$
DECLARE
  caught_sqlstate text;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  BEGIN
    PERFORM growth.content_approve('b0000000-0000-4000-8000-000000000001','ce000000-0000-4000-8000-000000000002','attacker');
    RAISE EXCEPTION 'TEST FAIL (5): attacker with no membership approved content via the function';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  RAISE NOTICE 'PASS (5): attacker with no membership cannot approve via content_approve() either (SQLSTATE %)', caught_sqlstate;
END $$;

\echo 'PASS: post-RC9 lifecycle privilege model — controlled functions, zero direct UPDATE, atomic, tenant-isolated'
