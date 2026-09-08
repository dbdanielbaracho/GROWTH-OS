-- Instagram authorization deduplication regression gate.
-- Verifies the security boundary and the runtime behavior for repeated OAuth attempts.
\set ON_ERROR_STOP on

BEGIN;

DO $dedup$
<<test_case>>
DECLARE
  status_oid oid;
  begin_oid oid;
  status_def text;
  begin_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  workspace_id uuid := 'b0000000-0000-4000-8000-000000000001';
  user_id uuid := 'a0000000-0000-4000-8000-000000000001';
  managed_id uuid := 'c0000000-0000-4000-8000-000000000911';
  authority_id uuid := 'c0000000-0000-4000-8000-000000000912';
  connected_id uuid := 'c0000000-0000-4000-8000-000000000913';
  stale_one_id uuid := 'c0000000-0000-4000-8000-000000000914';
  stale_two_id uuid := 'c0000000-0000-4000-8000-000000000915';
  social_id uuid := 'c0000000-0000-4000-8000-000000000916';
  returned_id uuid;
  visible_count integer;
  total_count integer;
  authorizing_count integer;
  superseded_count integer;
  visible_state text;
BEGIN
  status_oid := to_regprocedure('growth.instagram_integration_status()');
  begin_oid := to_regprocedure('growth.instagram_begin_authorization(uuid,text[])');

  IF status_oid IS NULL OR begin_oid IS NULL THEN
    RAISE EXCEPTION '039 failed: Instagram deduplication helpers are missing';
  END IF;

  SELECT pg_get_functiondef(status_oid) INTO status_def;
  SELECT pg_get_functiondef(begin_oid) INTO begin_def;

  IF position('left join lateral' IN lower(status_def)) = 0
     OR position('when ''connected'' then 0' IN lower(status_def)) = 0
     OR position('limit 1' IN lower(status_def)) = 0
  THEN
    RAISE EXCEPTION '039 failed: status helper does not project one prioritized connection';
  END IF;

  IF position('instagram_authorization_superseded' IN lower(begin_def)) = 0
     OR position('state=''authorizing''' IN lower(begin_def)) = 0
     OR position('state in (''revoked'',' IN lower(begin_def)) = 0
     OR position('if connection_id is null' IN lower(begin_def)) = 0
     OR position('for update' IN lower(begin_def)) = 0
  THEN
    RAISE EXCEPTION '039 failed: authorization helper does not supersede stale authorizations safely';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid=p.proowner
  WHERE p.oid=status_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '039 failed: status helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', status_oid, 'EXECUTE')
    INTO app_execute;
  IF app_execute IS DISTINCT FROM true THEN
    RAISE EXCEPTION '039 failed: app_runtime cannot execute status helper';
  END IF;

  SELECT has_function_privilege('public', status_oid, 'EXECUTE')
    INTO public_execute;
  IF public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION '039 failed: PUBLIC can execute status helper';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid=p.proowner
  WHERE p.oid=begin_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '039 failed: begin helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', begin_oid, 'EXECUTE')
    INTO app_execute;
  IF app_execute IS DISTINCT FROM true THEN
    RAISE EXCEPTION '039 failed: app_runtime cannot execute begin helper';
  END IF;

  SELECT has_function_privilege('public', begin_oid, 'EXECUTE')
    INTO public_execute;
  IF public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION '039 failed: PUBLIC can execute begin helper';
  END IF;

  IF has_table_privilege('app_runtime','growth.platform_connections','SELECT')
     OR has_table_privilege('app_runtime','growth.platform_connections','INSERT')
     OR has_table_privilege('app_runtime','growth.platform_connections','UPDATE')
     OR has_table_privilege('app_runtime','growth.platform_connections','DELETE')
  THEN
    RAISE EXCEPTION '039 failed: direct runtime platform connection access widened';
  END IF;

  PERFORM set_config('app.workspace_id',workspace_id::text,true);
  PERFORM set_config('app.user_id',user_id::text,true);

  INSERT INTO growth.managed_accounts(
    id,workspace_id,owner_type,authority_status,contribution_eligibility,authority_clause_ref
  ) VALUES (
    managed_id,workspace_id,'direct','contractually_granted','eligible','test-039'
  );

  INSERT INTO growth.authority_history(
    id,workspace_id,managed_account_id,owner_type,authority_status,
    contribution_eligibility,authority_clause_ref,effective_from,effective_to
  ) VALUES (
    authority_id,workspace_id,managed_id,'direct','contractually_granted',
    'eligible','test-039','2026-09-01T00:00:00Z'::timestamptz,NULL
  );

  INSERT INTO growth.platform_connections(
    id,workspace_id,managed_account_id,platform,state
  ) VALUES
    (connected_id,workspace_id,managed_id,'instagram','connected'),
    (stale_one_id,workspace_id,managed_id,'instagram','authorizing'),
    (stale_two_id,workspace_id,managed_id,'instagram','authorizing');

  UPDATE growth.platform_connections
  SET updated_at=now()-interval '2 minutes'
  WHERE id=stale_one_id;

  UPDATE growth.platform_connections
  SET updated_at=now()-interval '1 minute'
  WHERE id=stale_two_id;

  INSERT INTO growth.social_accounts(
    id,workspace_id,managed_account_id,platform_connection_id,platform,
    provider_account_id,handle,account_type,market,timezone
  ) VALUES (
    social_id,workspace_id,managed_id,connected_id,'instagram',
    'instagram-039-gate','@instagram-039-gate','business','US','UTC'
  );

  SET LOCAL ROLE app_runtime;

  SELECT count(*), max(connection_state)
    INTO visible_count, visible_state
  FROM growth.instagram_integration_status();

  IF visible_count <> 1 OR visible_state <> 'connected' THEN
    RAISE EXCEPTION '039 failed: repeated authorizations were not projected as one connected row';
  END IF;

  SELECT growth.instagram_begin_authorization(
    managed_id, ARRAY['instagram_business_basic']::text[]
  ) INTO returned_id;

  IF returned_id IS NULL THEN
    RAISE EXCEPTION '039 failed: begin authorization returned no connection';
  END IF;

  RESET ROLE;

  SELECT count(*),
         count(*) FILTER (WHERE state='authorizing'),
         count(*) FILTER (
           WHERE state='failed'
             AND error_class='instagram_authorization_superseded'
         )
    INTO total_count, authorizing_count, superseded_count
  FROM growth.platform_connections pc
  WHERE pc.workspace_id=test_case.workspace_id
    AND pc.managed_account_id=test_case.managed_id
    AND pc.platform='instagram';

  IF total_count <> 3 OR authorizing_count <> 1 OR superseded_count <> 1 THEN
    RAISE EXCEPTION
      '039 failed: expected 3 total, 1 authorizing and 1 superseded row; got %, %, %',
      total_count, authorizing_count, superseded_count;
  END IF;

  SET LOCAL ROLE app_runtime;

  SELECT count(*), max(connection_state)
    INTO visible_count, visible_state
  FROM growth.instagram_integration_status();

  IF visible_count <> 1 OR visible_state <> 'connected' THEN
    RAISE EXCEPTION '039 failed: status exposed duplicate rows after a new authorization';
  END IF;

  RESET ROLE;
END;
$dedup$;

ROLLBACK;

\echo 'PASS 039_instagram_authorization_deduplication'
