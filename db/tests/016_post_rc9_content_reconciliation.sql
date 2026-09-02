-- Growth OS — Post-RC9 Content Domain reconciliation, structural + RLS
-- adversarial tests. Every assertion here was physically proven at least
-- once during the design rounds before being encoded as a permanent test.

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- Fixtures from db/provisioning/test/03_test_fixtures.sql assumed present:
--   own_ws    = b0000000-0000-4000-8000-000000000001 (legit_owner active owner)
--   victim_ws = b0000000-0000-4000-8000-000000000002 (legit_owner active owner)
--   legit_owner = a0000000-0000-4000-8000-000000000001
--   attacker    = a0000000-0000-4000-8000-000000000002 (zero memberships anywhere)

-- ============================================================
-- Setup: a content_version in each workspace.
-- ============================================================
DO $$
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);

  INSERT INTO growth.content_items(id,workspace_id,market,language,source_type,status) VALUES
    ('ca000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','US','en','manual','ready_for_review'),
    ('ca000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000002','US','en','manual','ready_for_review')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO growth.content_versions(id,workspace_id,content_item_id,version_no,body,checksum) VALUES
    ('ca000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','ca000000-0000-4000-8000-000000000001',1,'own body','chk-post-rc9-own'),
    ('ca000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000002','ca000000-0000-4000-8000-000000000003',1,'victim body','chk-post-rc9-victim')
  ON CONFLICT (id) DO NOTHING;

  RESET ROLE;
END $$;

-- ============================================================
-- 1a) RLS-layer defense: session context is own_ws, but the row claims
--     a content_version_id that belongs to victim_ws. content_version_visible()
--     requires the EXACT (workspace_id, content_version_id) pair to exist,
--     so this is caught by RLS's WITH CHECK before the FK is even reached
--     — RLS is now at least as strict as the FK for this exact case, a
--     stronger result than the original (pre-hardening) design round,
--     where the FK alone caught it (42501 vs 23503 depending on which
--     layer runs first is an implementation detail; what matters is that
--     the row is rejected either way).
-- ============================================================
DO $$
DECLARE
  caught_sqlstate text;
  caught_message text;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  BEGIN
    INSERT INTO growth.content_approvals(id,workspace_id,content_version_id,actor_user_id,decision)
    VALUES('ca000000-0000-4000-8000-000000000005','b0000000-0000-4000-8000-000000000001','ca000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000001','approved');
    RAISE EXCEPTION 'TEST FAIL (1a): cross-workspace content_version_id (own workspace_id claimed) was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE, caught_message = MESSAGE_TEXT;
  END;
  RESET ROLE;
  IF caught_sqlstate NOT IN ('42501','23503') THEN
    RAISE EXCEPTION 'TEST FAIL (1a): unexpected SQLSTATE %, expected 42501 (RLS) or 23503 (FK)', caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (1a): cross-workspace content_version_id rejected — SQLSTATE % (%), RLS content_version_visible() and the composite FK now overlap in coverage for this case', caught_sqlstate, caught_message;
END $$;

-- ============================================================
-- 1b) FK-layer defense, isolated: growth_test_harness has BYPASSRLS, so
--     this proves the FK alone (independent of RLS) also rejects a
--     genuinely impossible (workspace_id, content_version_id) pair —
--     defense-in-depth confirmed to be real, not merely theoretical.
-- ============================================================
DO $$
DECLARE
  caught_sqlstate text;
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  BEGIN
    INSERT INTO growth.content_approvals(id,workspace_id,content_version_id,actor_user_id,decision)
    VALUES('ca000000-0000-4000-8000-000000000011','b0000000-0000-4000-8000-000000000001','ca000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000001','approved');
    RAISE EXCEPTION 'TEST FAIL (1b): FK accepted a cross-workspace pair even bypassing RLS entirely';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  IF caught_sqlstate <> '23503' THEN
    RAISE EXCEPTION 'TEST FAIL (1b): unexpected SQLSTATE %, expected 23503 (FK), with RLS bypassed entirely', caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (1b): with RLS fully bypassed (growth_test_harness), the composite FK alone still rejects a cross-workspace pair — confirms it is a real, independent layer, not redundant';
END $$;

-- ============================================================
-- 2) RLS WITH CHECK: row workspace_id matches the FK target, but session
--    context is a different workspace.
-- ============================================================
DO $$
DECLARE
  caught_sqlstate text;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  BEGIN
    INSERT INTO growth.content_approvals(id,workspace_id,content_version_id,actor_user_id,decision)
    VALUES('ca000000-0000-4000-8000-000000000005','b0000000-0000-4000-8000-000000000002','ca000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000001','approved');
    RAISE EXCEPTION 'TEST FAIL (2): row matching FK but not session context was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  IF caught_sqlstate <> '42501' THEN
    RAISE EXCEPTION 'TEST FAIL (2): unexpected SQLSTATE %, expected 42501', caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (2): RLS WITH CHECK rejects workspace_id/session mismatch';
END $$;

-- ============================================================
-- 3) Attacker with zero memberships anywhere: INSERT and SELECT both
--    denied.
-- ============================================================
DO $$
DECLARE
  caught_sqlstate text;
  visible_rows int;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000002', true);
  BEGIN
    INSERT INTO growth.content_approvals(id,workspace_id,content_version_id,actor_user_id,decision)
    VALUES('ca000000-0000-4000-8000-000000000005','b0000000-0000-4000-8000-000000000002','ca000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000002','approved');
    RAISE EXCEPTION 'TEST FAIL (3 insert): attacker with zero memberships inserted successfully';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  SELECT count(*) INTO visible_rows FROM growth.content_approvals WHERE workspace_id = 'b0000000-0000-4000-8000-000000000002'::uuid;
  RESET ROLE;
  IF caught_sqlstate <> '42501' THEN
    RAISE EXCEPTION 'TEST FAIL (3 insert): unexpected SQLSTATE %', caught_sqlstate;
  END IF;
  IF visible_rows <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (3 select): attacker saw % row(s)', visible_rows;
  END IF;
  RAISE NOTICE 'PASS (3): attacker with zero memberships denied on both INSERT and SELECT';
END $$;

-- ============================================================
-- 4) Revoked membership: previously-active member of own_ws, now
--    revoked, must see zero content_approvals rows there.
-- ============================================================
DO $$
DECLARE
  visible_rows int;
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
  VALUES('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','viewer',false,'active')
  ON CONFLICT (workspace_id,user_id) DO UPDATE SET status = 'active';
  UPDATE growth.memberships SET status = 'revoked'
   WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001'::uuid AND user_id = 'a0000000-0000-4000-8000-000000000003'::uuid;
  RESET ROLE;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000003', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  SELECT count(*) INTO visible_rows FROM growth.content_approvals WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001'::uuid;
  RESET ROLE;

  IF visible_rows <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (4): revoked member saw % row(s)', visible_rows;
  END IF;
  RAISE NOTICE 'PASS (4): revoked membership sees zero content_approvals rows';
END $$;

-- ============================================================
-- 5) Tombstoned content: an approval referencing a since-tombstoned
--    content_item's version must become invisible, exactly mirroring
--    content_items/content_versions' own tombstone behavior.
-- ============================================================
DO $$
DECLARE
  visible_before int;
  visible_after int;
  item_visible int;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.content_approvals(id,workspace_id,content_version_id,actor_user_id,decision)
  VALUES('ca000000-0000-4000-8000-000000000006','b0000000-0000-4000-8000-000000000001','ca000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','approved');
  SELECT count(*) INTO visible_before FROM growth.content_approvals WHERE id = 'ca000000-0000-4000-8000-000000000006'::uuid;
  RESET ROLE;
  IF visible_before <> 1 THEN
    RAISE EXCEPTION 'TEST SETUP FAIL (5): approval did not insert as expected';
  END IF;

  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.deletion_requests(id,workspace_id,requested_by,scope,target_id,state,manifest_version)
  VALUES('ca000000-0000-4000-8000-000000000007','b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','content','ca000000-0000-4000-8000-000000000001','tombstoned','v1')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.deletion_tombstones(workspace_id,target_type,target_id,deletion_request_id,effective_at)
  VALUES('b0000000-0000-4000-8000-000000000001','content','ca000000-0000-4000-8000-000000000001','ca000000-0000-4000-8000-000000000007',now())
  ON CONFLICT (workspace_id,target_type,target_id) DO NOTHING;
  RESET ROLE;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  SELECT count(*) INTO item_visible FROM growth.content_items WHERE id = 'ca000000-0000-4000-8000-000000000001'::uuid;
  SELECT count(*) INTO visible_after FROM growth.content_approvals WHERE id = 'ca000000-0000-4000-8000-000000000006'::uuid;
  RESET ROLE;

  IF item_visible <> 0 THEN
    RAISE EXCEPTION 'TEST SETUP FAIL (5): content_items still visible after tombstone, cannot validate the dependent check';
  END IF;
  IF visible_after <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL (5): content_approvals still exposes a row referencing tombstoned content — % row(s) visible', visible_after;
  END IF;
  RAISE NOTICE 'PASS (5): content_approvals correctly hides rows referencing tombstoned content, matching content_items/content_versions';
END $$;

-- ============================================================
-- 6) content_localizations: both sides must be independently live. A
--    tombstoned source must block visibility even when the localized
--    side is perfectly healthy.
-- ============================================================
DO $$
DECLARE
  caught_sqlstate text;
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.content_items(id,workspace_id,market,language,source_type,status)
  VALUES('ca000000-0000-4000-8000-000000000008','b0000000-0000-4000-8000-000000000001','BR','pt-BR','manual','ready_for_review')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.content_versions(id,workspace_id,content_item_id,version_no,body,checksum)
  VALUES('ca000000-0000-4000-8000-000000000009','b0000000-0000-4000-8000-000000000001','ca000000-0000-4000-8000-000000000008',1,'localized body','chk-post-rc9-loc')
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  BEGIN
    -- ca...0002 is the version behind the already-tombstoned ca...0001 item.
    INSERT INTO growth.content_localizations(id,workspace_id,source_content_version_id,localized_content_version_id)
    VALUES('ca000000-0000-4000-8000-00000000000a','b0000000-0000-4000-8000-000000000001','ca000000-0000-4000-8000-000000000002','ca000000-0000-4000-8000-000000000009');
    RAISE EXCEPTION 'TEST FAIL (6): localization with tombstoned source was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  IF caught_sqlstate <> '42501' THEN
    RAISE EXCEPTION 'TEST FAIL (6): unexpected SQLSTATE %', caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (6): content_localizations rejects a tombstoned source even with a healthy localized side';
END $$;

-- ============================================================
-- 7) Positive control: legitimate, healthy localization succeeds, and
--    target_market/target_language derive correctly via JOIN (no
--    duplicated columns).
-- ============================================================
DO $$
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000002', true);
  INSERT INTO growth.content_localizations(id,workspace_id,source_content_version_id,localized_content_version_id)
  VALUES('ca000000-0000-4000-8000-00000000000b','b0000000-0000-4000-8000-000000000002','ca000000-0000-4000-8000-000000000004','ca000000-0000-4000-8000-000000000004');
  RESET ROLE;
  RAISE EXCEPTION 'TEST FAIL (7 setup): self-referencing localization was accepted, CHECK constraint missing';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS (7 setup check): self-reference correctly rejected by CHECK constraint (source <> localized)';
END $$;

DO $$
DECLARE
  derived_market text;
  derived_language text;
BEGIN
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.content_items(id,workspace_id,market,language,source_type,status)
  VALUES('ca000000-0000-4000-8000-00000000000c','b0000000-0000-4000-8000-000000000001','BR','pt-BR','manual','ready_for_review')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.content_versions(id,workspace_id,content_item_id,version_no,body,checksum)
  VALUES('ca000000-0000-4000-8000-00000000000d','b0000000-0000-4000-8000-000000000001','ca000000-0000-4000-8000-00000000000c',1,'positive control loc','chk-post-rc9-loc-ok')
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;

  -- Use a source version that is NOT behind the tombstoned item: ca...0002
  -- belongs to the now-tombstoned ca...0001, so build a fresh source too.
  SET ROLE growth_test_harness;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.content_items(id,workspace_id,market,language,source_type,status)
  VALUES('ca000000-0000-4000-8000-00000000000e','b0000000-0000-4000-8000-000000000001','US','en','manual','ready_for_review')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO growth.content_versions(id,workspace_id,content_item_id,version_no,body,checksum)
  VALUES('ca000000-0000-4000-8000-00000000000f','b0000000-0000-4000-8000-000000000001','ca000000-0000-4000-8000-00000000000e',1,'positive control src','chk-post-rc9-src-ok')
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;

  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  INSERT INTO growth.content_localizations(id,workspace_id,source_content_version_id,localized_content_version_id)
  VALUES('ca000000-0000-4000-8000-000000000010','b0000000-0000-4000-8000-000000000001','ca000000-0000-4000-8000-00000000000f','ca000000-0000-4000-8000-00000000000d');

  SELECT ci.market, ci.language INTO derived_market, derived_language
  FROM growth.content_localizations cl
  JOIN growth.content_versions cv ON cv.id = cl.localized_content_version_id AND cv.workspace_id = cl.workspace_id
  JOIN growth.content_items ci ON ci.id = cv.content_item_id AND ci.workspace_id = cl.workspace_id
  WHERE cl.id = 'ca000000-0000-4000-8000-000000000010'::uuid;
  RESET ROLE;

  IF derived_market <> 'BR' OR derived_language <> 'pt-BR' THEN
    RAISE EXCEPTION 'TEST FAIL (7): derived target_market/language wrong: % / %', derived_market, derived_language;
  END IF;
  RAISE NOTICE 'PASS (7): legitimate localization succeeds, target_market/language derive correctly via JOIN, no duplicated columns';
END $$;

\echo 'PASS: post-RC9 content reconciliation — structural and RLS adversarial tests complete'
