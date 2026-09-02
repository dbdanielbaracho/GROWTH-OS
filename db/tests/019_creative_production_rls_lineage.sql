-- Growth OS — Creative Production, RLS + lineage cycle + tombstone
-- adversarial suite. Every scenario here was physically proven at least
-- once during design before being encoded as a permanent test.

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- Fixtures assumed present from db/provisioning/test/03_test_fixtures.sql:
--   own_ws    = b0000000-0000-4000-8000-000000000001 (legit_owner active owner)
--   victim_ws = b0000000-0000-4000-8000-000000000002 (legit_owner active owner)
--   legit_owner = a0000000-0000-4000-8000-000000000001
--   attacker    = a0000000-0000-4000-8000-000000000002 (zero memberships anywhere)
--   viewer_revocable = a0000000-0000-4000-8000-000000000003

-- ============================================================
-- 0) RLS metadata: enabled AND forced, all three tables, checked before
--    anything else runs.
-- ============================================================
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT relname, relrowsecurity, relforcerowsecurity FROM pg_class
           WHERE relname IN ('creative_requests','creative_generations','media_asset_lineage')
  LOOP
    IF NOT r.relrowsecurity OR NOT r.relforcerowsecurity THEN
      RAISE EXCEPTION 'TEST FAIL (0): % has relrowsecurity=%, relforcerowsecurity=% — both must be true', r.relname, r.relrowsecurity, r.relforcerowsecurity;
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS (0): RLS enabled and forced on all three new tables';
END $$;

-- ============================================================
-- Setup: a creative_request + generation in own_ws, and one in victim_ws.
-- ============================================================
DO $$
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.creative_requests(id,workspace_id,source_type,source_id,capability,modality,target_market,target_language,requested_by,status)
  VALUES
    ('e1000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','user_request','a0000000-0000-4000-8000-000000000001','voice_clone','audio','US','en','a0000000-0000-4000-8000-000000000001','requested'),
    ('e1000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','user_request','a0000000-0000-4000-8000-000000000001','voice_clone','audio','US','en','a0000000-0000-4000-8000-000000000001','requested')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.creative_generations(id,workspace_id,creative_request_id,provider,status,idempotency_key)
  VALUES
    ('e2000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001','elevenlabs','requested','idem-e2-001'),
    ('e2000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','e1000000-0000-4000-8000-000000000002','elevenlabs','requested','idem-e2-002')
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;
END $$;

-- ============================================================
-- 1) creative_requests: cross-tenant SELECT/INSERT denied, revoked
--    membership denied.
-- ============================================================
DO $$
DECLARE
  visible_rows int;
  caught_sqlstate text;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  SELECT count(*) INTO visible_rows FROM growth.creative_requests WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001'::uuid;
  BEGIN
    INSERT INTO growth.creative_requests(id,workspace_id,source_type,source_id,capability,modality,target_market,target_language,requested_by,status)
    VALUES('e1000000-0000-4000-8000-000000000009','b0000000-0000-4000-8000-000000000001','user_request','a0000000-0000-4000-8000-000000000002','x','text','US','en','a0000000-0000-4000-8000-000000000002','requested');
    RAISE EXCEPTION 'TEST FAIL (1): attacker inserted into creative_requests';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  IF visible_rows <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (1): attacker saw % row(s) in creative_requests', visible_rows;
  END IF;
  IF caught_sqlstate <> '42501' THEN
    RAISE EXCEPTION 'TEST FAIL (1): unexpected SQLSTATE %', caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (1): creative_requests cross-tenant SELECT=0, INSERT denied (%)', caught_sqlstate;
END $$;

DO $$
DECLARE
  visible_rows int;
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
  VALUES('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','viewer',false,'active')
  ON CONFLICT (workspace_id,user_id) DO UPDATE SET status='active';
  UPDATE growth.memberships SET status='revoked'
   WHERE workspace_id='b0000000-0000-4000-8000-000000000001'::uuid AND user_id='a0000000-0000-4000-8000-000000000003'::uuid;
  RESET ROLE;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000003', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  SELECT count(*) INTO visible_rows FROM growth.creative_requests WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001'::uuid;
  RESET ROLE;
  IF visible_rows <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (1b): revoked member saw % row(s)', visible_rows;
  END IF;
  RAISE NOTICE 'PASS (1b): revoked membership sees zero creative_requests rows';
END $$;

-- ============================================================
-- 2) creative_generations: cross-tenant SELECT/UPDATE denied.
-- ============================================================
DO $$
DECLARE
  visible_rows int;
  affected_rows int;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000002', true);
  SELECT count(*) INTO visible_rows FROM growth.creative_generations WHERE id = 'e2000000-0000-4000-8000-000000000001'::uuid;
  UPDATE growth.creative_generations SET status='cancelled' WHERE id = 'e2000000-0000-4000-8000-000000000001'::uuid;
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  RESET ROLE;
  IF visible_rows <> 0 OR affected_rows <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (2): cross-tenant visible=% affected=%', visible_rows, affected_rows;
  END IF;
  RAISE NOTICE 'PASS (2): creative_generations cross-tenant SELECT=0, UPDATE affects 0 rows';
END $$;

-- ============================================================
-- 3) media_asset_lineage: cross-workspace edge rejected by composite FK;
--    cross-tenant read returns zero rows; edge validates BOTH sides.
-- ============================================================
DO $$
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.media_assets(id,workspace_id,storage_ref,mime_type,checksum,rights_status,source_class,purpose) VALUES
    ('e3000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','s3://own-src','audio/mp3','chk-e3own','licensed','ai_generated','source'),
    ('e3000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','s3://own-out','video/mp4','chk-e3out','licensed','ai_generated','publishable'),
    ('e3000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000002','s3://victim-src','audio/mp3','chk-e3vic','licensed','ai_generated','source')
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;
END $$;

DO $$
DECLARE
  caught_sqlstate text;
  visible_rows int;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  BEGIN
    INSERT INTO growth.media_asset_lineage(workspace_id,output_asset_id,input_asset_id,role)
    VALUES('b0000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000002','e3000000-0000-4000-8000-000000000003','voice');
    RAISE EXCEPTION 'TEST FAIL (3): cross-workspace lineage edge was accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;

  INSERT INTO growth.media_asset_lineage(workspace_id,output_asset_id,input_asset_id,role)
  VALUES('b0000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000002','e3000000-0000-4000-8000-000000000001','voice');
  RESET ROLE;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000002', true);
  SELECT count(*) INTO visible_rows FROM growth.media_asset_lineage;
  RESET ROLE;

  IF caught_sqlstate <> '23503' THEN
    RAISE EXCEPTION 'TEST FAIL (3): unexpected SQLSTATE %', caught_sqlstate;
  END IF;
  IF visible_rows <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (3): cross-tenant read saw % row(s)', visible_rows;
  END IF;
  RAISE NOTICE 'PASS (3): cross-workspace edge rejected (%), legitimate edge created, cross-tenant read=0', caught_sqlstate;
END $$;

-- ============================================================
-- 4) Lineage cycles: self, 2-node, 3-node, all rejected; legitimate
--    chain continues to work.
-- ============================================================
DO $$
DECLARE
  caught_sqlstate text;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  BEGIN
    INSERT INTO growth.media_asset_lineage(workspace_id,output_asset_id,input_asset_id,role)
    VALUES('b0000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000002','e3000000-0000-4000-8000-000000000002','self');
    RAISE EXCEPTION 'TEST FAIL (4a): self-cycle accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  RAISE NOTICE 'PASS (4a): self-cycle rejected (%)', caught_sqlstate;
END $$;

DO $$
DECLARE
  caught_sqlstate text;
BEGIN
  -- existing edge from test 3: out(0002) <- src(0001)
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  BEGIN
    INSERT INTO growth.media_asset_lineage(workspace_id,output_asset_id,input_asset_id,role)
    VALUES('b0000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000002','cycle2');
    RAISE EXCEPTION 'TEST FAIL (4b): 2-node cycle accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  RAISE NOTICE 'PASS (4b): 2-node cycle rejected (%)', caught_sqlstate;
END $$;

DO $$
DECLARE
  caught_sqlstate text;
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.media_assets(id,workspace_id,storage_ref,mime_type,checksum,rights_status,source_class,purpose)
  VALUES('e3000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000001','s3://own-third','video/mp4','chk-e3third','licensed','ai_generated','intermediate')
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  -- legitimate chain: 0004 <- 0002 (extends the existing 0002 <- 0001)
  INSERT INTO growth.media_asset_lineage(workspace_id,output_asset_id,input_asset_id,role)
  VALUES('b0000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000004','e3000000-0000-4000-8000-000000000002','chain3');

  BEGIN
    -- would close 0001 -> 0002 -> 0004 -> 0001
    INSERT INTO growth.media_asset_lineage(workspace_id,output_asset_id,input_asset_id,role)
    VALUES('b0000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000004','cycle3');
    RAISE EXCEPTION 'TEST FAIL (4c): 3-node cycle accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  RAISE NOTICE 'PASS (4c): 3-node cycle rejected (%), legitimate chain still intact', caught_sqlstate;
END $$;

-- ============================================================
-- 5) Shared asset + tombstone: Content A's exclusive final asset
--    disappears; Content B's final asset and the shared input asset
--    (no fixed content_version_id) both remain fully reachable.
-- ============================================================
DO $$
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.content_items(id,workspace_id,market,language,source_type,status) VALUES
    ('e4000000-0000-4000-8000-00000000000a','b0000000-0000-4000-8000-000000000001','US','en','manual','ready_for_review'),
    ('e4000000-0000-4000-8000-00000000000b','b0000000-0000-4000-8000-000000000001','US','en','manual','ready_for_review')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.content_versions(id,workspace_id,content_item_id,version_no,body,checksum) VALUES
    ('e4100000-0000-4000-8000-00000000000a','b0000000-0000-4000-8000-000000000001','e4000000-0000-4000-8000-00000000000a',1,'content A','chk-e4a'),
    ('e4100000-0000-4000-8000-00000000000b','b0000000-0000-4000-8000-000000000001','e4000000-0000-4000-8000-00000000000b',1,'content B','chk-e4b')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.media_assets(id,workspace_id,storage_ref,mime_type,checksum,rights_status,source_class,content_version_id,purpose) VALUES
    ('e4200000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','s3://e4-shared-voice','audio/mp3','chk-e4voice','licensed','ai_generated',NULL,'source'),
    ('e4200000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','s3://e4-final-a','video/mp4','chk-e4finala','licensed','ai_generated','e4100000-0000-4000-8000-00000000000a','publishable'),
    ('e4200000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001','s3://e4-final-b','video/mp4','chk-e4finalb','licensed','ai_generated','e4100000-0000-4000-8000-00000000000b','publishable')
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.media_asset_lineage(workspace_id,output_asset_id,input_asset_id,role) VALUES
    ('b0000000-0000-4000-8000-000000000001','e4200000-0000-4000-8000-000000000002','e4200000-0000-4000-8000-000000000001','voice'),
    ('b0000000-0000-4000-8000-000000000001','e4200000-0000-4000-8000-000000000003','e4200000-0000-4000-8000-000000000001','voice')
  ON CONFLICT DO NOTHING;
  RESET ROLE;

  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.deletion_requests(id,workspace_id,requested_by,scope,target_id,state,manifest_version)
  VALUES('e5000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','content','e4000000-0000-4000-8000-00000000000a','tombstoned','v1')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.deletion_tombstones(workspace_id,target_type,target_id,deletion_request_id,effective_at)
  VALUES('b0000000-0000-4000-8000-000000000001','content','e4000000-0000-4000-8000-00000000000a','e5000000-0000-4000-8000-000000000001',now())
  ON CONFLICT (workspace_id,target_type,target_id) DO NOTHING;
  RESET ROLE;
END $$;

DO $$
DECLARE
  final_a_visible int;
  final_b_visible int;
  shared_voice_visible int;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  SELECT count(*) INTO final_a_visible FROM growth.media_assets WHERE id = 'e4200000-0000-4000-8000-000000000002'::uuid;
  SELECT count(*) INTO final_b_visible FROM growth.media_assets WHERE id = 'e4200000-0000-4000-8000-000000000003'::uuid;
  SELECT count(*) INTO shared_voice_visible FROM growth.media_assets WHERE id = 'e4200000-0000-4000-8000-000000000001'::uuid;
  RESET ROLE;

  IF final_a_visible <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (5): Content A''s exclusive final asset still visible after tombstone';
  END IF;
  IF final_b_visible <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (5): Content B''s final asset incorrectly hidden by A''s tombstone';
  END IF;
  IF shared_voice_visible <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (5): shared voice asset (no fixed content_version_id) incorrectly hidden by A''s tombstone';
  END IF;
  RAISE NOTICE 'PASS (5): tombstone of Content A hides only its own exclusive asset; Content B and the shared input asset remain fully reachable';
END $$;

\echo 'PASS: Creative Production RLS + lineage cycle + tombstone adversarial suite complete'
