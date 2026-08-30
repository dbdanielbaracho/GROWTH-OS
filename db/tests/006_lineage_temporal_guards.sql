-- Growth OS RC9 — lineage/temporal guards, partially executable.
-- Replaces the RC8 comment-only file of the same name for L2 and L3, which
-- are self-contained (no publication/experiment fixture graph required).
--
-- L1 (publication lineage) and T1 (experiment/exposure/outcome chronology)
-- require a large fixture graph (social_accounts, platform_connections,
-- managed_accounts, hypotheses, experiments, exposures) not built in this
-- round. They remain NOT EXECUTED here — do not infer PASS for them from
-- this file's exit code.

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- ============================================================
-- L2 — a content variant cannot declare itself as its own source.
-- ============================================================
DO $$
DECLARE
  caught_sqlstate text;
  rows_before int;
  rows_after int;
  same_version uuid := 'd0000000-0000-4000-8000-000000000001';
BEGIN
  SET ROLE growth_test_harness;
  INSERT INTO growth.content_items(id,workspace_id,market,language,source_type,status)
  VALUES('d0000000-0000-4000-8000-0000000000c1','b0000000-0000-4000-8000-000000000001'::uuid,'US','en','manual','draft')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.content_versions(id,workspace_id,content_item_id,version_no,body,checksum)
  VALUES(same_version,'b0000000-0000-4000-8000-000000000001'::uuid,'d0000000-0000-4000-8000-0000000000c1'::uuid,1,'x','deadbeef')
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;

  SELECT count(*) INTO rows_before FROM growth.content_variants
   WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001'::uuid;

  BEGIN
    INSERT INTO growth.content_variants(id,workspace_id,source_content_version_id,variant_content_version_id)
    VALUES('d0000000-0000-4000-8000-0000000000c2'::uuid,'b0000000-0000-4000-8000-000000000001'::uuid,same_version,same_version);
    RAISE EXCEPTION 'TEST FAIL (L2): self-referencing content variant was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;

  IF caught_sqlstate IS DISTINCT FROM '23514' THEN
    RAISE EXCEPTION 'TEST FAIL (L2): unexpected SQLSTATE %, expected 23514 (check_violation)', caught_sqlstate;
  END IF;

  SELECT count(*) INTO rows_after FROM growth.content_variants
   WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001'::uuid;
  IF rows_after IS DISTINCT FROM rows_before THEN
    RAISE EXCEPTION 'TEST FAIL (L2): row count changed despite rejection';
  END IF;
  RAISE NOTICE 'PASS (L2): self-referencing content variant rejected by CHECK constraint';
END $$;

-- ============================================================
-- L3 — insight demotion graph must remain acyclic.
-- ============================================================
DO $$
DECLARE
  ws uuid := 'b0000000-0000-4000-8000-000000000001';
  ia uuid := 'e0000000-0000-4000-8000-00000000000a';
  ib uuid := 'e0000000-0000-4000-8000-00000000000b';
  ic uuid := 'e0000000-0000-4000-8000-00000000000c';
  caught_sqlstate text;
BEGIN
  SET ROLE growth_test_harness;
  INSERT INTO growth.insights(id,workspace_id,state,claim,logic_version,valid_from) VALUES
    (ia,ws,'account_hypothesis','L3 node A','vtest',clock_timestamp()),
    (ib,ws,'account_hypothesis','L3 node B','vtest',clock_timestamp()),
    (ic,ws,'account_hypothesis','L3 node C','vtest',clock_timestamp())
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;

  -- Direct self-cycle: A demoted_from A must fail.
  BEGIN
    UPDATE growth.insights SET demoted_from = ia WHERE id = ia AND workspace_id = ws;
    RAISE EXCEPTION 'TEST FAIL (L3 self-cycle): self-reference was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  IF caught_sqlstate NOT IN ('23514','P0001') THEN
    RAISE EXCEPTION 'TEST FAIL (L3 self-cycle): unexpected SQLSTATE %', caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (L3 self-cycle): direct self-reference rejected';

  -- Build acyclic A->B->C first (must succeed).
  UPDATE growth.insights SET demoted_from = NULL WHERE id IN (ia,ib,ic) AND workspace_id = ws;
  UPDATE growth.insights SET demoted_from = ib WHERE id = ia AND workspace_id = ws;
  UPDATE growth.insights SET demoted_from = ic WHERE id = ib AND workspace_id = ws;
  RAISE NOTICE 'PASS (L3 acyclic): A->B->C chain accepted';

  -- Now attempt C -> A, which would close the cycle A->B->C->A.
  BEGIN
    UPDATE growth.insights SET demoted_from = ia WHERE id = ic AND workspace_id = ws;
    RAISE EXCEPTION 'TEST FAIL (L3 3-hop cycle): A->B->C->A was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  IF caught_sqlstate NOT IN ('23514','P0001') THEN
    RAISE EXCEPTION 'TEST FAIL (L3 3-hop cycle): unexpected SQLSTATE %', caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (L3 3-hop cycle): A->B->C->A correctly rejected';
END $$;

\echo 'PASS: L2 and L3 executed and verified. L1 and T1 remain NOT EXECUTED — require publication and experiment fixture graphs not built in this round.'
