-- Growth OS — Instagram token lifecycle and reconnect/revocation.
-- Forward-only migration. Extends 017 without widening app_runtime table access.
-- Provider credentials remain behind SECURITY DEFINER helpers.

\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.instagram_begin_authorization(
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
  connection_id uuid;
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

  SELECT pc.id INTO connection_id
  FROM growth.platform_connections pc
  WHERE pc.workspace_id=ws
    AND pc.managed_account_id=p_managed_account_id
    AND pc.platform='instagram'
    AND pc.state IN ('revoked','disconnected','reauth_required','failed')
  ORDER BY pc.updated_at DESC
  LIMIT 1
  FOR UPDATE OF pc;

  IF connection_id IS NULL THEN
    connection_id := gen_random_uuid();
    INSERT INTO growth.platform_connections(
      id,workspace_id,managed_account_id,platform,state,credential_ciphertext,
      granted_scopes,created_at,updated_at
    )
    VALUES(connection_id,ws,p_managed_account_id,'instagram','authorizing',NULL,
           p_scopes,now(),now());
  ELSE
    UPDATE growth.platform_connections
    SET state='authorizing',
        credential_ciphertext=NULL,
        granted_scopes=p_scopes,
        token_expires_at=NULL,
        error_class=NULL,
        updated_at=now()
    WHERE workspace_id=ws AND id=connection_id;
  END IF;

  RETURN connection_id;
END;
$$;

ALTER FUNCTION growth.instagram_begin_authorization(uuid,text[]) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.instagram_begin_authorization(uuid,text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_begin_authorization(uuid,text[]) TO app_runtime;

CREATE OR REPLACE FUNCTION growth.instagram_complete_authorization(
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
  social_id uuid;
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

  SELECT sa.id INTO social_id
  FROM growth.social_accounts sa
  WHERE sa.platform='instagram'
    AND sa.provider_account_id=p_provider_account_id;

  IF social_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM growth.social_accounts sa
    WHERE sa.id=social_id
      AND sa.workspace_id=ws
      AND sa.platform_connection_id=p_connection_id
  ) THEN
    RAISE EXCEPTION 'instagram account is already connected';
  END IF;

  INSERT INTO growth.provider_credentials(
    workspace_id,platform_connection_id,provider,credential_ciphertext,
    cipher_version,key_version,token_expires_at,refresh_available,updated_at
  )
  VALUES(ws,p_connection_id,'instagram',p_credential_ciphertext,p_cipher_version,
         p_key_version,p_token_expires_at,p_refresh_available,now())
  ON CONFLICT (workspace_id,platform_connection_id) DO UPDATE
  SET provider='instagram',
      credential_ciphertext=EXCLUDED.credential_ciphertext,
      cipher_version=EXCLUDED.cipher_version,
      key_version=EXCLUDED.key_version,
      token_expires_at=EXCLUDED.token_expires_at,
      refresh_available=EXCLUDED.refresh_available,
      updated_at=now();

  UPDATE growth.platform_connections
  SET state='connected',credential_ciphertext=NULL,granted_scopes=p_scopes,
      token_expires_at=p_token_expires_at,last_success_at=now(),
      last_failure_at=NULL,error_class=NULL,updated_at=now()
  WHERE workspace_id=ws AND id=p_connection_id;

  IF social_id IS NULL THEN
    social_id := gen_random_uuid();
    INSERT INTO growth.social_accounts(
      id,workspace_id,managed_account_id,platform_connection_id,platform,
      provider_account_id,handle,account_type,market,timezone,created_at
    )
    VALUES(
      social_id,ws,managed_id,p_connection_id,'instagram',p_provider_account_id,
      nullif(btrim(coalesce(p_handle,'')),''),nullif(btrim(coalesce(p_account_type,'')),''),
      nullif(btrim(coalesce(p_market,'')),''),nullif(btrim(coalesce(p_timezone,'')),''),now()
    );
  ELSE
    UPDATE growth.social_accounts
    SET managed_account_id=managed_id,
        handle=nullif(btrim(coalesce(p_handle,'')),''),
        account_type=nullif(btrim(coalesce(p_account_type,'')),''),
        market=nullif(btrim(coalesce(p_market,'')),''),
        timezone=nullif(btrim(coalesce(p_timezone,'')),'')
    WHERE workspace_id=ws AND id=social_id;
  END IF;

  RETURN social_id;
END;
$$;

ALTER FUNCTION growth.instagram_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[]) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.instagram_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[]) TO app_runtime;

CREATE FUNCTION growth.instagram_revoke_connection(p_connection_id uuid)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ws uuid := growth.current_workspace_id();
  actor uuid := growth.current_app_user_id();
BEGIN
  IF ws IS NULL OR actor IS NULL OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'instagram revocation requires active tenant context';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM growth.platform_connections pc
    JOIN growth.managed_accounts ma
      ON ma.workspace_id=pc.workspace_id AND ma.id=pc.managed_account_id
    WHERE pc.workspace_id=ws
      AND pc.id=p_connection_id
      AND pc.platform='instagram'
      AND pc.state IN ('connected','degraded','reauth_required','failed','authorizing')
      AND ma.authority_status='contractually_granted'
  ) THEN
    RETURN false;
  END IF;

  DELETE FROM growth.provider_credentials
  WHERE workspace_id=ws AND platform_connection_id=p_connection_id;

  UPDATE growth.platform_connections
  SET state='revoked',
      credential_ciphertext=NULL,
      granted_scopes='{}',
      token_expires_at=NULL,
      error_class='instagram_user_revoked',
      updated_at=now()
  WHERE workspace_id=ws AND id=p_connection_id;

  RETURN FOUND;
END;
$$;

ALTER FUNCTION growth.instagram_revoke_connection(uuid) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.instagram_revoke_connection(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_revoke_connection(uuid) TO app_runtime;

COMMIT;
