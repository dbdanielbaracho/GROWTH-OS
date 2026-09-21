-- Growth OS — user-controlled YouTube connection revocation.
-- Forward-only migration 073. Removes stored OAuth material immediately while
-- preserving the channel identity required for a safe same-channel reconnect.

\set ON_ERROR_STOP on

BEGIN;
SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.youtube_update_connection_credential(
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
    RAISE EXCEPTION 'youtube credential update requires active tenant context';
  END IF;
  IF coalesce(octet_length(p_credential_ciphertext), 0) = 0
     OR btrim(coalesce(p_cipher_version, '')) = ''
     OR btrim(coalesce(p_key_version, '')) = ''
     OR cardinality(p_scopes) IS NULL
     OR cardinality(p_scopes) = 0
  THEN
    RAISE EXCEPTION 'youtube credential update requires complete credential metadata';
  END IF;
  IF NOT EXISTS (
    SELECT 1
      FROM growth.platform_connections pc
      JOIN growth.managed_accounts ma
        ON ma.workspace_id = pc.workspace_id AND ma.id = pc.managed_account_id
      JOIN growth.social_accounts sa
        ON sa.workspace_id = pc.workspace_id AND sa.platform_connection_id = pc.id
     WHERE pc.workspace_id = ws
       AND pc.id = p_connection_id
       AND pc.platform = 'youtube'
       AND pc.state IN ('connected','degraded','reauth_required','failed','revoked')
       AND sa.platform = 'youtube'
       AND ma.authority_status = 'contractually_granted'
  ) THEN
    RETURN false;
  END IF;

  INSERT INTO growth.provider_credentials(
    workspace_id, platform_connection_id, provider, credential_ciphertext,
    cipher_version, key_version, token_expires_at, refresh_available, updated_at
  ) VALUES (
    ws, p_connection_id, 'youtube', p_credential_ciphertext,
    p_cipher_version, p_key_version, p_token_expires_at, p_refresh_available, now()
  )
  ON CONFLICT (workspace_id, platform_connection_id) DO UPDATE
  SET provider = EXCLUDED.provider,
      credential_ciphertext = EXCLUDED.credential_ciphertext,
      cipher_version = EXCLUDED.cipher_version,
      key_version = EXCLUDED.key_version,
      token_expires_at = EXCLUDED.token_expires_at,
      refresh_available = EXCLUDED.refresh_available,
      updated_at = now();

  UPDATE growth.platform_connections
     SET state = 'connected',
         granted_scopes = p_scopes,
         token_expires_at = p_token_expires_at,
         last_success_at = now(),
         error_class = NULL,
         updated_at = now()
   WHERE workspace_id = ws AND id = p_connection_id;

  RETURN FOUND;
END;
$$;

ALTER FUNCTION growth.youtube_update_connection_credential(uuid,bytea,text,text,timestamptz,boolean,text[]) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.youtube_update_connection_credential(uuid,bytea,text,text,timestamptz,boolean,text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.youtube_update_connection_credential(uuid,bytea,text,text,timestamptz,boolean,text[]) TO app_runtime;

CREATE FUNCTION growth.youtube_revoke_connection(p_connection_id uuid)
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
    RAISE EXCEPTION 'youtube revocation requires active tenant context';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM growth.platform_connections pc
      JOIN growth.managed_accounts ma
        ON ma.workspace_id = pc.workspace_id AND ma.id = pc.managed_account_id
     WHERE pc.workspace_id = ws
       AND pc.id = p_connection_id
       AND pc.platform = 'youtube'
       AND pc.state IN ('connected','degraded','reauth_required','failed','authorizing')
       AND ma.authority_status = 'contractually_granted'
  ) THEN
    RETURN false;
  END IF;

  DELETE FROM growth.provider_credentials
   WHERE workspace_id = ws AND platform_connection_id = p_connection_id;

  UPDATE growth.platform_connections
     SET state = 'revoked',
         credential_ciphertext = NULL,
         granted_scopes = '{}',
         token_expires_at = NULL,
         error_class = 'youtube_user_revoked',
         updated_at = now()
   WHERE workspace_id = ws AND id = p_connection_id;

  RETURN FOUND;
END;
$$;

ALTER FUNCTION growth.youtube_revoke_connection(uuid) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.youtube_revoke_connection(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.youtube_revoke_connection(uuid) TO app_runtime;

COMMIT;
