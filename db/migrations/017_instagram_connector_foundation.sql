-- Growth OS — Instagram connector foundation.
-- Uses Instagram API with Instagram Login for professional accounts.
-- Credentials remain encrypted in provider_credentials; app_runtime sees only
-- narrow SECURITY DEFINER helpers.

BEGIN;

INSERT INTO growth.capabilities(
  id,platform,market,account_type,capability,status,required_scopes,limits,
  media_constraints,app_review_status,provider_api_version,validated_at,
  evidence_ref,evidence_status,adapter_version,kill_switch,updated_at
)
VALUES
  (gen_random_uuid(),'instagram','GLOBAL','professional','authorized_profile','validation_required',
   ARRAY['instagram_business_basic'],
   '{"login":"instagram_login"}'::jsonb,'{}'::jsonb,'not_submitted',
   'instagram-api-with-instagram-login',now(),
   'https://developers.facebook.com/documentation/instagram-platform/instagram-api-with-instagram-login',
   'verified','instagram-v0.1',false,now()),
  (gen_random_uuid(),'instagram','GLOBAL','professional','content_publish','validation_required',
   ARRAY['instagram_business_basic','instagram_business_content_publish'],
   '{"media_container":"required"}'::jsonb,
   '{"formats":["image","video","reels"],"caption_max_length":2200}'::jsonb,
   'not_submitted','instagram-api-with-instagram-login',now(),
   'https://developers.facebook.com/documentation/instagram-platform/content-publishing',
   'verified','instagram-v0.1',true,now()),
  (gen_random_uuid(),'instagram','GLOBAL','professional','authorized_insights','validation_required',
   ARRAY['instagram_business_basic','instagram_business_manage_insights'],
   '{"account_type":"professional"}'::jsonb,'{}'::jsonb,'not_submitted',
   'instagram-api-with-instagram-login',now(),
   'https://developers.facebook.com/documentation/instagram-platform/instagram-api-with-instagram-login',
   'verified','instagram-v0.1',true,now())
ON CONFLICT (platform,market,account_type,capability) DO UPDATE
SET status=EXCLUDED.status,
    required_scopes=EXCLUDED.required_scopes,
    limits=EXCLUDED.limits,
    media_constraints=EXCLUDED.media_constraints,
    app_review_status=EXCLUDED.app_review_status,
    provider_api_version=EXCLUDED.provider_api_version,
    validated_at=EXCLUDED.validated_at,
    evidence_ref=EXCLUDED.evidence_ref,
    evidence_status=EXCLUDED.evidence_status,
    adapter_version=EXCLUDED.adapter_version,
    kill_switch=EXCLUDED.kill_switch,
    updated_at=now();

CREATE FUNCTION growth.instagram_integration_status()
RETURNS TABLE(
  managed_account_id uuid,
  owner_type text,
  authority_status text,
  contribution_eligibility text,
  connection_id uuid,
  connection_state text,
  connection_updated_at timestamptz,
  social_account_id uuid,
  provider_account_id text,
  handle text,
  account_type text,
  market text,
  source_timezone text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT ma.id,ma.owner_type,ma.authority_status,ma.contribution_eligibility,
         pc.id,pc.state,pc.updated_at,sa.id,sa.provider_account_id,sa.handle,
         sa.account_type,sa.market,sa.timezone
  FROM growth.managed_accounts ma
  LEFT JOIN growth.platform_connections pc
    ON pc.workspace_id=ma.workspace_id
   AND pc.managed_account_id=ma.id
   AND pc.platform='instagram'
  LEFT JOIN growth.social_accounts sa
    ON sa.workspace_id=pc.workspace_id
   AND sa.platform_connection_id=pc.id
   AND sa.platform='instagram'
  WHERE ma.workspace_id=growth.current_workspace_id()
    AND growth.tenant_context_valid(ma.workspace_id)
  ORDER BY ma.id,pc.created_at DESC NULLS LAST;
$$;
ALTER FUNCTION growth.instagram_integration_status() OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.instagram_integration_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_integration_status() TO app_runtime;

CREATE FUNCTION growth.instagram_begin_authorization(
  p_managed_account_id uuid,
  p_scopes text[]
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ws uuid := growth.current_workspace_id();
  actor uuid := growth.current_app_user_id();
  connection_id uuid := gen_random_uuid();
BEGIN
  IF ws IS NULL OR actor IS NULL OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'instagram authorization requires active tenant context';
  END IF;
  IF cardinality(p_scopes) IS NULL OR cardinality(p_scopes)=0 THEN
    RAISE EXCEPTION 'instagram authorization requires scopes';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.managed_accounts ma
    WHERE ma.workspace_id=ws
      AND ma.id=p_managed_account_id
      AND ma.authority_status='contractually_granted'
  ) THEN
    RAISE EXCEPTION 'instagram authorization requires a contractually granted managed account';
  END IF;

  INSERT INTO growth.platform_connections(
    id,workspace_id,managed_account_id,platform,state,credential_ciphertext,
    granted_scopes,created_at,updated_at
  )
  VALUES(connection_id,ws,p_managed_account_id,'instagram','authorizing',NULL,
         p_scopes,now(),now());
  RETURN connection_id;
END;
$$;
ALTER FUNCTION growth.instagram_begin_authorization(uuid,text[]) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.instagram_begin_authorization(uuid,text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_begin_authorization(uuid,text[]) TO app_runtime;

CREATE FUNCTION growth.instagram_complete_authorization(
  p_connection_id uuid,
  p_provider_account_id text,
  p_handle text,
  p_account_type text,
  p_market text,
  p_timezone text,
  p_credential_ciphertext bytea,
  p_cipher_version text,
  p_key_version text,
  p_token_expires_at timestamptz,
  p_refresh_available boolean,
  p_scopes text[]
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ws uuid := growth.current_workspace_id();
  actor uuid := growth.current_app_user_id();
  managed_id uuid;
  social_id uuid := gen_random_uuid();
BEGIN
  IF ws IS NULL OR actor IS NULL OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'instagram callback requires active tenant context';
  END IF;
  IF btrim(coalesce(p_provider_account_id,''))='' OR octet_length(p_credential_ciphertext)=0 THEN
    RAISE EXCEPTION 'instagram callback missing account or credential';
  END IF;

  SELECT pc.managed_account_id INTO managed_id
  FROM growth.platform_connections pc
  JOIN growth.managed_accounts ma
    ON ma.workspace_id=pc.workspace_id AND ma.id=pc.managed_account_id
  WHERE pc.workspace_id=ws AND pc.id=p_connection_id
    AND pc.platform='instagram' AND pc.state='authorizing'
    AND ma.authority_status='contractually_granted'
  FOR UPDATE OF pc;

  IF managed_id IS NULL THEN
    RAISE EXCEPTION 'instagram authorization state is not valid';
  END IF;

  IF EXISTS (
    SELECT 1 FROM growth.social_accounts sa
    WHERE sa.platform='instagram' AND sa.provider_account_id=p_provider_account_id
  ) THEN
    RAISE EXCEPTION 'instagram account is already connected';
  END IF;

  INSERT INTO growth.provider_credentials(
    workspace_id,platform_connection_id,provider,credential_ciphertext,
    cipher_version,key_version,token_expires_at,refresh_available,updated_at
  )
  VALUES(ws,p_connection_id,'instagram',p_credential_ciphertext,p_cipher_version,
         p_key_version,p_token_expires_at,p_refresh_available,now());

  UPDATE growth.platform_connections
  SET state='connected',credential_ciphertext=NULL,granted_scopes=p_scopes,
      token_expires_at=p_token_expires_at,last_success_at=now(),
      last_failure_at=NULL,error_class=NULL,updated_at=now()
  WHERE workspace_id=ws AND id=p_connection_id;

  INSERT INTO growth.social_accounts(
    id,workspace_id,managed_account_id,platform_connection_id,platform,
    provider_account_id,handle,account_type,market,timezone,created_at
  )
  VALUES(
    social_id,ws,managed_id,p_connection_id,'instagram',p_provider_account_id,
    nullif(btrim(coalesce(p_handle,'')),''),nullif(btrim(coalesce(p_account_type,'')),''), 
    nullif(btrim(coalesce(p_market,'')),''),nullif(btrim(coalesce(p_timezone,'')),''),now()
  );
  RETURN social_id;
END;
$$;
ALTER FUNCTION growth.instagram_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[]) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.instagram_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[]) TO app_runtime;

CREATE FUNCTION growth.instagram_get_connection_credential(p_connection_id uuid)
RETURNS TABLE(
  social_account_id uuid,
  provider_account_id text,
  credential_ciphertext bytea,
  cipher_version text,
  key_version text,
  token_expires_at timestamptz,
  refresh_available boolean,
  granted_scopes text[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT sa.id,sa.provider_account_id,pcd.credential_ciphertext,pcd.cipher_version,
         pcd.key_version,pcd.token_expires_at,pcd.refresh_available,pc.granted_scopes
  FROM growth.platform_connections pc
  JOIN growth.managed_accounts ma
    ON ma.workspace_id=pc.workspace_id AND ma.id=pc.managed_account_id
  JOIN growth.social_accounts sa
    ON sa.workspace_id=pc.workspace_id AND sa.platform_connection_id=pc.id
  JOIN growth.provider_credentials pcd
    ON pcd.workspace_id=pc.workspace_id AND pcd.platform_connection_id=pc.id
  WHERE pc.workspace_id=growth.current_workspace_id()
    AND pc.id=p_connection_id AND pc.platform='instagram' AND pc.state='connected'
    AND ma.authority_status='contractually_granted'
    AND growth.tenant_context_valid(pc.workspace_id)
  LIMIT 1;
$$;
ALTER FUNCTION growth.instagram_get_connection_credential(uuid) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.instagram_get_connection_credential(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_get_connection_credential(uuid) TO app_runtime;

CREATE FUNCTION growth.instagram_update_connection_credential(
  p_connection_id uuid,
  p_credential_ciphertext bytea,
  p_cipher_version text,
  p_key_version text,
  p_token_expires_at timestamptz,
  p_refresh_available boolean,
  p_scopes text[]
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE ws uuid := growth.current_workspace_id();
BEGIN
  IF ws IS NULL OR growth.current_app_user_id() IS NULL OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'instagram credential update requires active tenant context';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.platform_connections pc
    JOIN growth.managed_accounts ma
      ON ma.workspace_id=pc.workspace_id AND ma.id=pc.managed_account_id
    WHERE pc.workspace_id=ws AND pc.id=p_connection_id AND pc.platform='instagram'
      AND pc.state='connected' AND ma.authority_status='contractually_granted'
  ) THEN
    RETURN false;
  END IF;

  UPDATE growth.provider_credentials
  SET credential_ciphertext=p_credential_ciphertext,cipher_version=p_cipher_version,
      key_version=p_key_version,token_expires_at=p_token_expires_at,
      refresh_available=p_refresh_available,updated_at=now()
  WHERE workspace_id=ws AND platform_connection_id=p_connection_id;
  IF NOT FOUND THEN RETURN false; END IF;

  UPDATE growth.platform_connections
  SET granted_scopes=p_scopes,token_expires_at=p_token_expires_at,
      last_success_at=now(),error_class=NULL,updated_at=now()
  WHERE workspace_id=ws AND id=p_connection_id;
  RETURN FOUND;
END;
$$;
ALTER FUNCTION growth.instagram_update_connection_credential(uuid,bytea,text,text,timestamptz,boolean,text[]) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.instagram_update_connection_credential(uuid,bytea,text,text,timestamptz,boolean,text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_update_connection_credential(uuid,bytea,text,text,timestamptz,boolean,text[]) TO app_runtime;

COMMIT;