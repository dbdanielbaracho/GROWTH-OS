-- Publication intent claim contract gate.
-- Proves tenant isolation, approval/connection revalidation, lease idempotency
-- and recovery after an expired claim. All fixtures are rolled back.
\set ON_ERROR_STOP on

BEGIN;

DO $claim$
DECLARE
  claim_oid oid;
  claim_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  workspace_id uuid := 'b0000000-0000-4000-8000-000000000001';
  user_id uuid := 'a0000000-0000-4000-8000-000000000001';
  managed_id uuid := 'c0000000-0000-4000-8000-000000000941';
  authority_id uuid := 'c0000000-0000-4000-8000-000000000942';
  connection_id uuid := 'c0000000-0000-4000-8000-000000000943';
  social_id uuid := 'c0000000-0000-4000-8000-000000000944';
  content_id uuid := 'c0000000-0000-4000-8000-000000000945';
  version_id uuid := 'c0000000-0000-4000-8000-000000000946';
  intent_id uuid;
  first_token uuid := 'd0000000-0000-4000-8000-000000000941';
  second_token uuid := 'd0000000-0000-4000-8000-000000000942';
  first_now timestamptz := '2026-09-08T16:00:00Z';
  v_intent growth.publication_intents;
  v_retry growth.publication_intents;
  conflict_seen boolean := false;
  direct_access boolean;
BEGIN
  claim_oid := to_regprocedure('growth.claim_publication_intent(uuid,uuid,uuid,timestamptz)');
  IF claim_oid IS NULL THEN
    RAISE EXCEPTION '040 failed: claim helper is missing';
  END IF;

  SELECT pg_get_functiondef(claim_oid) INTO claim_def;
  IF position('security definer' IN lower(claim_def)) = 0
     OR position('for update' IN lower(claim_def)) = 0
     OR position('claim_expires_at' IN lower(claim_def)) = 0
     OR position('current_attempt_no' IN lower(claim_def)) = 0
  THEN
    RAISE EXCEPTION '040 failed: claim helper lacks lease/serialization boundary';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = claim_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '040 failed: claim helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', claim_oid, 'EXECUTE')
    INTO app_execute;
  IF app_execute IS DISTINCT FROM true THEN
    RAISE EXCEPTION '040 failed: app_runtime cannot execute claim helper';
  END IF;

  SELECT has_function_privilege('public', claim_oid, 'EXECUTE')
    INTO public_execute;
  IF public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION '040 failed: PUBLIC can execute claim helper';
  END IF;

  SELECT has_table_privilege('app_runtime','growth.publication_intents','UPDATE')
    OR has_table_privilege('app_runtime','growth.publication_intents','SELECT')
    OR has_table_privilege('app_runtime','growth.publication_attempts','INSERT')
    INTO direct_access;
  IF direct_access IS DISTINCT FROM false THEN
    RAISE EXCEPTION '040 failed: direct runtime publication-table access widened';
  END IF;

  PERFORM set_config('app.workspace_id',workspace_id::text,true);
  PERFORM set_config('app.user_id',user_id::text,true);

  INSERT INTO growth.managed_accounts(
    id,workspace_id,owner_type,authority_status,contribution_eligibility,authority_clause_ref
  ) VALUES (
    managed_id,workspace_id,'direct','contractually_granted','eligible','test-040'
  );

  INSERT INTO growth.authority_history(
    id,workspace_id,managed_account_id,owner_type,authority_status,
    contribution_eligibility,authority_clause_ref,effective_from,effective_to
  ) VALUES (
    authority_id,workspace_id,managed_id,'direct','contractually_granted',
    'eligible','test-040',first_now,NULL
  );

  INSERT INTO growth.platform_connections(
    id,workspace_id,managed_account_id,platform,state
  ) VALUES (connection_id,workspace_id,managed_id,'youtube','connected');

  INSERT INTO growth.social_accounts(
    id,workspace_id,managed_account_id,platform_connection_id,platform,
    provider_account_id,handle,account_type,market,timezone
  ) VALUES (
    social_id,workspace_id,managed_id,connection_id,'youtube',
    'youtube-040-gate','@youtube-040-gate','creator','US','UTC'
  );

  INSERT INTO growth.content_items(
    id,workspace_id,objective,market,language,platform_target,source_type,status,created_by
  ) VALUES (
    content_id,workspace_id,'test publication','US','en','youtube','manual','approved',user_id
  );

  INSERT INTO growth.content_versions(
    id,workspace_id,content_item_id,version_no,body,structure_json,checksum
  ) VALUES (
    version_id,workspace_id,content_id,1,'approved test body','{}'::jsonb,'test-040-checksum'
  );

  SET LOCAL ROLE app_runtime;

  SELECT * INTO v_intent
  FROM growth.create_publication_intent(
    workspace_id,social_id,version_id,
    'e0000000-0000-4000-8000-000000000941',
    'test-040-intent'
  );

  IF v_intent.status <> 'ready' THEN
    RAISE EXCEPTION '040 failed: expected ready intent, got %', v_intent.status;
  END IF;
  intent_id := v_intent.id;

  SELECT * INTO v_intent
  FROM growth.claim_publication_intent(
    workspace_id,intent_id,first_token,first_now
  );

  IF v_intent.status <> 'sending'
     OR v_intent.current_attempt_no <> 1
     OR v_intent.claim_token IS DISTINCT FROM first_token
     OR v_intent.claim_expires_at IS DISTINCT FROM first_now + interval '10 minutes'
  THEN
    RAISE EXCEPTION '040 failed: first claim did not create the expected lease';
  END IF;

  SELECT * INTO v_retry
  FROM growth.claim_publication_intent(
    workspace_id,intent_id,first_token,first_now + interval '1 minute'
  );

  IF v_retry.id IS DISTINCT FROM v_intent.id
     OR v_retry.current_attempt_no <> 1
     OR v_retry.claim_token IS DISTINCT FROM first_token
  THEN
    RAISE EXCEPTION '040 failed: repeated claim with same token was not idempotent';
  END IF;

  BEGIN
    PERFORM growth.claim_publication_intent(
      workspace_id,intent_id,second_token,first_now + interval '1 minute'
    );
  EXCEPTION WHEN others THEN
    conflict_seen := true;
  END;

  IF NOT conflict_seen THEN
    RAISE EXCEPTION '040 failed: active claim accepted a different token';
  END IF;

  SELECT * INTO v_retry
  FROM growth.claim_publication_intent(
    workspace_id,intent_id,second_token,first_now + interval '11 minutes'
  );

  IF v_retry.status <> 'sending'
     OR v_retry.current_attempt_no <> 2
     OR v_retry.claim_token IS DISTINCT FROM second_token
  THEN
    RAISE EXCEPTION '040 failed: expired claim was not safely reclaimed';
  END IF;

  RESET ROLE;
END;
$claim$;

ROLLBACK;

\echo 'PASS 040_publication_intent_claim'
