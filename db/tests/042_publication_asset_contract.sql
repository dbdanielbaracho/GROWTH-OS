-- Publication asset binding contract gate.
-- Proves the selected asset is publishable, version-bound and tenant-bound.
\set ON_ERROR_STOP on

BEGIN;

DO $asset_contract$
DECLARE
  asset_oid oid;
  asset_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  workspace_id uuid := 'b0000000-0000-4000-8000-000000000001';
  user_id uuid := 'a0000000-0000-4000-8000-000000000001';
  managed_id uuid := 'c0000000-0000-4000-8000-000000000961';
  authority_id uuid := 'c0000000-0000-4000-8000-000000000962';
  connection_id uuid := 'c0000000-0000-4000-8000-000000000963';
  social_id uuid := 'c0000000-0000-4000-8000-000000000964';
  content_id uuid := 'c0000000-0000-4000-8000-000000000965';
  version_id uuid := 'c0000000-0000-4000-8000-000000000966';
  invalid_content_id uuid := 'c0000000-0000-4000-8000-000000000967';
  invalid_version_id uuid := 'c0000000-0000-4000-8000-000000000968';
  asset_id uuid := 'c0000000-0000-4000-8000-000000000969';
  invalid_asset_id uuid := 'c0000000-0000-4000-8000-000000000970';
  intent_row growth.publication_intents;
  invalid_seen boolean := false;
BEGIN
  asset_oid := to_regprocedure(
    'growth.create_publication_intent(uuid,uuid,uuid,uuid,text,uuid)'
  );
  IF asset_oid IS NULL THEN
    RAISE EXCEPTION '042 failed: asset-aware publication helper is missing';
  END IF;

  SELECT pg_get_functiondef(asset_oid) INTO asset_def;
  IF position('security definer' IN lower(asset_def)) = 0
     OR position('media_asset_id' IN lower(asset_def)) = 0
     OR position('publishable' IN lower(asset_def)) = 0
  THEN
    RAISE EXCEPTION '042 failed: helper does not enforce publishable asset binding';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = asset_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '042 failed: helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', asset_oid, 'EXECUTE')
    INTO app_execute;
  IF app_execute IS DISTINCT FROM true THEN
    RAISE EXCEPTION '042 failed: app_runtime cannot execute asset-aware helper';
  END IF;

  SELECT has_function_privilege('public', asset_oid, 'EXECUTE')
    INTO public_execute;
  IF public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION '042 failed: PUBLIC can execute asset-aware helper';
  END IF;

  PERFORM set_config('app.workspace_id', workspace_id::text, true);
  PERFORM set_config('app.user_id', user_id::text, true);

  INSERT INTO growth.managed_accounts(
    id,workspace_id,owner_type,authority_status,contribution_eligibility,authority_clause_ref
  ) VALUES (
    managed_id,workspace_id,'direct','contractually_granted','eligible','test-042'
  );

  INSERT INTO growth.authority_history(
    id,workspace_id,managed_account_id,owner_type,authority_status,
    contribution_eligibility,authority_clause_ref,effective_from
  ) VALUES (
    authority_id,workspace_id,managed_id,'direct','contractually_granted',
    'eligible','test-042',now()
  );

  INSERT INTO growth.platform_connections(
    id,workspace_id,managed_account_id,platform,state
  ) VALUES (connection_id,workspace_id,managed_id,'instagram','connected');

  INSERT INTO growth.social_accounts(
    id,workspace_id,managed_account_id,platform_connection_id,platform,
    provider_account_id,handle,account_type,market,timezone
  ) VALUES (
    social_id,workspace_id,managed_id,connection_id,'instagram',
    'instagram-042-gate','@instagram-042-gate','business','US','UTC'
  );

  INSERT INTO growth.content_items(
    id,workspace_id,objective,market,language,platform_target,source_type,status,created_by
  ) VALUES (
    content_id,workspace_id,'test asset contract','US','en',
    'instagram','manual','approved',user_id
  );

  INSERT INTO growth.content_versions(
    id,workspace_id,content_item_id,version_no,body,structure_json,checksum
  ) VALUES (
    version_id,workspace_id,content_id,1,'approved asset body',
    '{}'::jsonb,'test-042-checksum'
  );

  INSERT INTO growth.media_assets(
    id,workspace_id,storage_ref,mime_type,checksum,rights_status,source_class,
    bytes,purpose,content_version_id
  ) VALUES (
    asset_id,workspace_id,'https://cdn.example.com/asset-042.jpg','image/jpeg',
    'asset-042-checksum','licensed','owned',1234,'publishable',version_id
  );

  INSERT INTO growth.content_items(
    id,workspace_id,objective,market,language,platform_target,source_type,status,created_by
  ) VALUES (
    invalid_content_id,workspace_id,'test invalid asset','US','en',
    'instagram','manual','approved',user_id
  );

  INSERT INTO growth.content_versions(
    id,workspace_id,content_item_id,version_no,body,structure_json,checksum
  ) VALUES (
    invalid_version_id,workspace_id,invalid_content_id,1,'invalid asset body',
    '{}'::jsonb,'test-042-invalid-checksum'
  );

  INSERT INTO growth.media_assets(
    id,workspace_id,storage_ref,mime_type,checksum,rights_status,source_class,
    bytes,purpose,content_version_id
  ) VALUES (
    invalid_asset_id,workspace_id,'https://cdn.example.com/asset-042-source.jpg','image/jpeg',
    'asset-042-source-checksum','licensed','owned',1234,'source',invalid_version_id
  );

  SET LOCAL ROLE app_runtime;

  SELECT * INTO intent_row
  FROM growth.create_publication_intent(
    workspace_id,social_id,version_id,
    'e0000000-0000-4000-8000-000000000961',
    'test-042-valid-intent',
    asset_id
  );

  IF intent_row.id IS NULL OR intent_row.media_asset_id IS DISTINCT FROM asset_id THEN
    RAISE EXCEPTION '042 failed: valid publishable asset was not bound';
  END IF;

  BEGIN
    PERFORM growth.create_publication_intent(
      workspace_id,social_id,invalid_version_id,
      'e0000000-0000-4000-8000-000000000962',
      'test-042-invalid-intent',
      invalid_asset_id
    );
  EXCEPTION WHEN others THEN
    invalid_seen := true;
  END;

  IF NOT invalid_seen THEN
    RAISE EXCEPTION '042 failed: non-publishable asset was accepted';
  END IF;

  RESET ROLE;
END;
$asset_contract$;

ROLLBACK;

\echo 'PASS 042_publication_asset_contract'
