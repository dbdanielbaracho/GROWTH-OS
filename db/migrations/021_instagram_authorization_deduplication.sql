-- Growth OS — Instagram authorization deduplication and status projection.
-- Forward-only migration. Keeps one visible connection per managed account.
-- Existing credentials remain behind SECURITY DEFINER helpers.

\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.instagram_integration_status()
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
  SELECT
    ma.id,
    ma.owner_type,
    ma.authority_status,
    ma.contribution_eligibility,
    pc.id,
    pc.state,
    pc.updated_at,
    sa.id,
    sa.provider_account_id,
    sa.handle,
    sa.account_type,
    sa.market,
    sa.timezone
  FROM growth.managed_accounts ma
  LEFT JOIN LATERAL (
    SELECT pc0.*
    FROM growth.platform_connections pc0
    WHERE pc0.workspace_id=ma.workspace_id
      AND pc0.managed_account_id=ma.id
      AND pc0.platform='instagram'
    ORDER BY
      CASE pc0.state
        WHEN 'connected' THEN 0
        WHEN 'degraded' THEN 1
        WHEN 'reauth_required' THEN 2
        WHEN 'authorizing' THEN 3
        WHEN 'failed' THEN 4
        WHEN 'revoked' THEN 5
        WHEN 'disconnected' THEN 6
        ELSE 7
      END,
      pc0.updated_at DESC NULLS LAST,
      pc0.created_at DESC NULLS LAST,
      pc0.id DESC
    LIMIT 1
  ) pc ON true
  LEFT JOIN LATERAL (
    SELECT sa0.*
    FROM growth.social_accounts sa0
    WHERE sa0.workspace_id=pc.workspace_id
      AND sa0.platform_connection_id=pc.id
      AND sa0.platform='instagram'
    ORDER BY sa0.created_at DESC NULLS LAST, sa0.id DESC
    LIMIT 1
  ) sa ON true
  WHERE ma.workspace_id=growth.current_workspace_id()
    AND growth.tenant_context_valid(ma.workspace_id)
  ORDER BY ma.id;
$$;

ALTER FUNCTION growth.instagram_integration_status() OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.instagram_integration_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_integration_status() TO app_runtime;

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

  PERFORM 1
  FROM growth.managed_accounts ma
  WHERE ma.workspace_id=ws
    AND ma.id=p_managed_account_id
    AND ma.authority_status='contractually_granted'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'instagram authorization requires a contractually granted managed account';
  END IF;

  UPDATE growth.platform_connections
  SET state='failed',
      error_class='instagram_authorization_superseded',
      last_failure_at=now(),
      updated_at=now()
  WHERE workspace_id=ws
    AND managed_account_id=p_managed_account_id
    AND platform='instagram'
    AND state='authorizing';

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
    VALUES(
      connection_id,ws,p_managed_account_id,'instagram','authorizing',NULL,
      p_scopes,now(),now()
    );
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

COMMIT;
\echo 'PASS 021_instagram_authorization_deduplication'
