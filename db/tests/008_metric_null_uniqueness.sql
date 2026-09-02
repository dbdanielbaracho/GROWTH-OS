-- Growth OS RC9 — metric NULL-window uniqueness, executable.
-- Replaces the RC8 "NOT SELF-CONTAINED" placeholder by embedding its own
-- fixtures instead of delegating to an unbuilt integration harness.
-- Proves: two metric_normalized rows for the same content item/metric_key/
-- logic_version, both with NULL window_start/window_end, are treated as
-- the same logical lifetime metric (UNIQUE NULLS NOT DISTINCT), not as
-- infinitely many distinct NULL-window duplicates.

\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  ws uuid := 'b0000000-0000-4000-8000-000000000001';
  ci uuid := 'f0000000-0000-4000-8000-000000000001';
  caught_sqlstate text;
  rows_after int;
BEGIN
  SET ROLE growth_test_harness;
  INSERT INTO growth.content_items(id,workspace_id,market,language,source_type,status)
  VALUES(ci,ws,'US','en','manual','draft')
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;

  -- growth.metric_normalized correctly has NO RUNTIME ACCESS grant to
  -- app_runtime per the approved RC9 grant matrix (no current route
  -- touches it). This test proves a schema-level UNIQUE constraint, which
  -- does not depend on which role performs the insert, so it runs as
  -- growth_test_harness rather than app_runtime — using app_runtime here
  -- would contradict the approved matrix, not validate it.
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', ws::text, true);
  INSERT INTO growth.metric_normalized(id,workspace_id,content_item_id,metric_key,value,logic_version)
  VALUES('f0000000-0000-4000-8000-000000000011'::uuid,ws,ci,'lifetime_engagement',10,'vtest');
  RESET ROLE;

  -- Second identical lifetime metric, same key/logic_version, both windows
  -- NULL: must be rejected as a duplicate, not silently accepted.
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', ws::text, true);
  BEGIN
    INSERT INTO growth.metric_normalized(id,workspace_id,content_item_id,metric_key,value,logic_version)
    VALUES('f0000000-0000-4000-8000-000000000012'::uuid,ws,ci,'lifetime_engagement',20,'vtest');
    RAISE EXCEPTION 'TEST FAIL: second NULL-window lifetime metric was accepted as a distinct row';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;

  IF caught_sqlstate IS DISTINCT FROM '23505' THEN
    RAISE EXCEPTION 'TEST FAIL: unexpected SQLSTATE %, expected 23505 (unique_violation)', caught_sqlstate;
  END IF;

  SELECT count(*) INTO rows_after FROM growth.metric_normalized
   WHERE content_item_id = ci AND metric_key = 'lifetime_engagement';
  IF rows_after <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL: expected exactly 1 row after rejected duplicate, found %', rows_after;
  END IF;

  RAISE NOTICE 'PASS: NULL-window lifetime metric behaves as one logical row, duplicate rejected with 23505';
END $$;

\echo 'PASS: metric NULL-window uniqueness verified'
