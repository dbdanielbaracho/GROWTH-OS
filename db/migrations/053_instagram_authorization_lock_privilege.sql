-- Growth OS — remove the authorization helper's hidden UPDATE dependency.
-- Migration 021 used SELECT ... FOR UPDATE on managed_accounts. PostgreSQL
-- requires UPDATE privilege for that lock mode, but growth_migrator is
-- intentionally read-only on managed_accounts. Serialize authorization
-- attempts with a transaction-scoped advisory lock instead.

\set ON_ERROR_STOP on

BEGIN;

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

  -- Serialize concurrent authorization attempts for this managed account
  -- without granting growth_migrator UPDATE on managed_accounts.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_managed_account_id::text, 0)
  );

  PERFORM 1
  FROM growth.managed_accounts ma
  WHERE ma.workspace_id=ws
    AND ma.id=p_managed_account_id
    AND ma.authority_status='contractually_granted';

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
