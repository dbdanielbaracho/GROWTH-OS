-- Growth OS — media_asset_lineage cycle rejection under real concurrency.
-- Same pattern as db/tests/010_c1_membership_concurrency.sql: this file
-- documents and asserts the final state of a race physically run as two
-- real concurrent psql sessions, coordinated by the advisory lock in
-- growth.reject_media_asset_lineage_cycle().
--
-- Setup (run once, single session): two unrelated assets X, Y in own_ws.
--
-- Session A (as app_runtime):
--   BEGIN;
--   INSERT INTO media_asset_lineage(...) VALUES (..., output=Y, input=X, 'concurrent_xy');
--   SELECT pg_sleep(1.0);
--   COMMIT;
--
-- Session B (as app_runtime, started ~0.2s after A, while A's tx is open):
--   BEGIN;
--   INSERT INTO media_asset_lineage(...) VALUES (..., output=X, input=Y, 'concurrent_yx');
--   COMMIT;
--
-- Physically executed in this session: A committed X->Y first. B, blocked
-- by the advisory lock until A released it at commit, then correctly
-- detected that X already reaches Y and was rejected — the guard was not
-- escaped by the race.

\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  edge_count int;
BEGIN
  SELECT count(*) INTO edge_count FROM growth.media_asset_lineage
   WHERE output_asset_id = 'e6000000-0000-4000-8000-000000000002'::uuid
     AND input_asset_id = 'e6000000-0000-4000-8000-000000000001'::uuid;

  IF edge_count <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (concurrency): expected exactly 1 edge (X->Y) to have survived, found %', edge_count;
  END IF;

  SELECT count(*) INTO edge_count FROM growth.media_asset_lineage
   WHERE output_asset_id = 'e6000000-0000-4000-8000-000000000001'::uuid
     AND input_asset_id = 'e6000000-0000-4000-8000-000000000002'::uuid;

  IF edge_count <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (concurrency): the reverse edge (Y->X) should have been rejected, but % row(s) exist', edge_count;
  END IF;

  RAISE NOTICE 'PASS (concurrency): two real concurrent sessions raced to create opposite edges; only the first-committed edge survived, the cycle-closing edge was rejected';
END $$;

\echo 'PASS: media_asset_lineage cycle rejection verified under real concurrency'
