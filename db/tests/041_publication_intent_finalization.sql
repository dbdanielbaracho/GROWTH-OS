-- Publication result finalization contract gate.
-- Proves immutable attempt persistence and idempotent result replay.
\set ON_ERROR_STOP on

BEGIN;

DO $finalize$
<<test_case>>
DECLARE
  finalize_oid oid;
  finalize_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  workspace_id uuid := 'b0000000-0000-4000-8000-000000000001';
  user_id uuid := 'a0000000-0000-4000-8000-000000000001';
  managed_id uuid := 'c0000000-0000-4000-8000-000000000951';
  authority_id uuid := 'c0000000-0000-4000-8000-000000000952';
  connection_id uuid := 'c0000000-0000-4000-8000-000000000953';
  social_id uuid := 'c0000000-0000-4000-8000-000000000954';
  content_id uuid := 'c0000000-0000-4000-8000-000000000955';
  version_id uuid := 'c0000000-0000-4000-8000-000000000956';
  intent_id uuid;
  claim_token uuid := 'd0000000-0000-4000-8000-000000000951';
  fixed_now timestamptz := '2026-09-08T16:30:00Z';
  v_intent growth.publication_intents;
  v_replay growth.publication_intents;
  direct_update boolean;
  conflict_seen boolean := false;
BEGIN
  finalize_oid := to_regprocedure(
    'growth.finalize_publication_intent(uuid,uuid,uuid,integer,text,text,integer,text,text,text,timestamptz,timestamptz,text)'
  );
  IF finalize_oid IS NULL THEN
    RAISE EXCEPTION '041 failed: finalization helper is missing';
  END IF;

  SELECT pg_get_functiondef(finalize_oid) INTO finalize_def;
  IF position('security definer' IN lower(finalize_def)) = 0
     OR position('publication_attempts' IN lower(finalize_def)) = 0
     OR position('claim_token' IN lower(finalize_def)) = 0
     OR position('immutable evidence' IN lower(finalize_def)) = 0
  THEN
    RAISE EXCEPTION '041 failed: finalization helper lacks immutable replay boundary';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = finalize_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '041 failed: finalization helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', finalize_oid, 'EXECUTE')
    INTO app_execute;
  IF app_execute IS DISTINCT FROM true THEN
    RAISE EXCEPTION '041 failed: app_runtime cannot execute finalization helper';
  END IF;

  SELECT has_function_privilege('public', finalize_oid, 'EXECUTE')
    INTO public_execute;
  IF public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION '041 failed: PUBLIC can execute finalization helper';
  END IF;

  SELECT has_table_privilege('app_runtime','growth.publication_intents','UPDATE')
    OR has_table_privilege('app_runtime','growth.publication_attempts','INSERT')
    OR has_table_privilege('app_runtime','growth.publication_attempts','UPDATE')
    INTO direct_update;
  IF direct_update IS DISTINCT FROM false THEN
    RAISE EXCEPTION '041 failed: direct runtime publication access widened';
  END IF;

  PERFORM set_config('app.workspace_id',workspace_id::text,true);
  PERFORM set_config('app.user_id',user_id::text,true);

  INSERT INTO growth.managed_accounts(
    id,workspace_id,owner_type,authority_status,contribution_eligibility,authority_clause_ref
  ) VALUES (
    managed_id,workspace_id,'direct','contractually_granted','eligible','test-041'
  );

  INSERT INTO growth.authority_history(
    id,workspace_id,managed_account_id,owner_type,authority_status,
    contribution_eligibility,authority_clause_ref,effective_from
  ) VALUES (
    authority_id,workspace_id,managed_id,'direct','contractually_granted',
    'eligible','test-041',fixed_now
  );

  INSERT INTO growth.platform_connections(
    id,workspace_id,managed_account_id,platform,state
  ) VALUES (connection_id,workspace_id,managed_id,'instagram','connected');

  INSERT INTO growth.social_accounts(
    id,workspace_id,managed_account_id,platform_connection_id,platform,
    provider_account_id,handle,account_type,market,timezone
  ) VALUES (
    social_id,workspace_id,managed_id,connection_id,'instagram',
    'instagram-041-gate','@instagram-041-gate','business','US','UTC'
  );

  INSERT INTO growth.content_items(
    id,workspace_id,objective,market,language,platform_target,source_type,status,created_by
  ) VALUES (
    content_id,workspace_id,'test publication finalization','US','en',
    'instagram','manual','approved',user_id
  );

  INSERT INTO growth.content_versions(
    id,workspace_id,content_item_id,version_no,body,structure_json,checksum
  ) VALUES (
    version_id,workspace_id,content_id,1,'approved finalization body',
    '{}'::jsonb,'test-041-checksum'
  );

  SET LOCAL ROLE app_runtime;

  SELECT * INTO v_intent
  FROM growth.create_publication_intent(
    workspace_id,social_id,version_id,
    'e0000000-0000-4000-8000-000000000951',
    'test-041-intent'
  );

  SELECT * INTO v_intent
  FROM growth.claim_publication_intent(
    workspace_id,v_intent.id,claim_token,fixed_now
  );

  SELECT * INTO v_intent
  FROM growth.finalize_publication_intent(
    workspace_id,v_intent.id,claim_token,1,'hash-041','confirmed',200,
    'provider-request-041','provider-content-041',
    'https://provider.example/content/041',fixed_now,
    fixed_now + interval '2 seconds','payload-ref-041'
  );

  IF v_intent.status <> 'confirmed'
     OR v_intent.provider_content_id <> 'provider-content-041'
     OR v_intent.provider_permalink <> 'https://provider.example/content/041'
     OR v_intent.claim_token IS NOT NULL
  THEN
    RAISE EXCEPTION '041 failed: confirmed finalization did not close the claim';
  END IF;

  -- The identical replay below proves the immutable attempt was persisted:
  -- without the row, finalization would reject because the claim is already closed.

  SET LOCAL ROLE app_runtime;

  SELECT * INTO v_replay
  FROM growth.finalize_publication_intent(
    workspace_id,v_intent.id,claim_token,1,'hash-041','confirmed',200,
    'provider-request-041','provider-content-041',
    'https://provider.example/content/041',fixed_now,
    fixed_now + interval '2 seconds','payload-ref-041'
  );

  IF v_replay.id IS DISTINCT FROM v_intent.id OR v_replay.status <> 'confirmed' THEN
    RAISE EXCEPTION '041 failed: identical finalization replay was not idempotent';
  END IF;

  BEGIN
    PERFORM growth.finalize_publication_intent(
      workspace_id,v_intent.id,claim_token,1,'hash-041','confirmed',200,
      'provider-request-041','different-content',
      'https://provider.example/content/041',fixed_now,
      fixed_now + interval '2 seconds','payload-ref-041'
    );
  EXCEPTION WHEN others THEN
    conflict_seen := true;
  END;

  IF NOT conflict_seen THEN
    RAISE EXCEPTION '041 failed: conflicting immutable attempt replay was accepted';
  END IF;

  RESET ROLE;
END;
$finalize$;

ROLLBACK;

\echo 'PASS 041_publication_intent_finalization'
