-- Growth OS — YouTube reauthorization cleanup and supersession.
-- Forward-only. Keeps an existing connected channel intact while ensuring a
-- fresh initial authorization cannot accumulate orphan authorizing rows.

\set ON_ERROR_STOP on

BEGIN;
SET search_path = growth, public;

-- Remove only abandoned YouTube authorization attempts that never acquired a
-- social account or credential. Connected/revoked historical rows are untouched.
DELETE FROM growth.platform_connections pc
WHERE pc.platform = 'youtube'
  AND pc.state = 'authorizing'
  AND pc.updated_at < now() - interval '5 minutes'
  AND NOT EXISTS (
    SELECT 1
    FROM growth.social_accounts sa
    WHERE sa.workspace_id = pc.workspace_id
      AND sa.platform_connection_id = pc.id
  )
  AND NOT EXISTS (
    SELECT 1
    FROM growth.provider_credentials pcd
    WHERE pcd.workspace_id = pc.workspace_id
      AND pcd.platform_connection_id = pc.id
  );

CREATE OR REPLACE FUNCTION growth.youtube_begin_authorization(
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
    RAISE EXCEPTION 'youtube authorization requires active tenant context';
  END IF;
  IF cardinality(p_scopes) IS NULL OR cardinality(p_scopes) = 0 THEN
    RAISE EXCEPTION 'youtube authorization requires scopes';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.managed_accounts ma
    WHERE ma.workspace_id = ws
      AND ma.id = p_managed_account_id
      AND ma.authority_status = 'contractually_granted'
  ) THEN
    RAISE EXCEPTION 'youtube authorization requires a contractually granted managed account';
  END IF;

  -- A newly started initial authorization supersedes an unfinished attempt for
  -- the same managed account. Rows already bound to a social account or stored
  -- credential are never deleted here.
  DELETE FROM growth.platform_connections pc
  WHERE pc.workspace_id = ws
    AND pc.managed_account_id = p_managed_account_id
    AND pc.platform = 'youtube'
    AND pc.state = 'authorizing'
    AND NOT EXISTS (
      SELECT 1
      FROM growth.social_accounts sa
      WHERE sa.workspace_id = pc.workspace_id
        AND sa.platform_connection_id = pc.id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM growth.provider_credentials pcd
      WHERE pcd.workspace_id = pc.workspace_id
        AND pcd.platform_connection_id = pc.id
    );

  INSERT INTO growth.platform_connections(
    id, workspace_id, managed_account_id, platform, state, credential_ciphertext,
    granted_scopes, created_at, updated_at
  ) VALUES (
    connection_id, ws, p_managed_account_id, 'youtube', 'authorizing', NULL,
    p_scopes, now(), now()
  );

  RETURN connection_id;
END;
$$;

ALTER FUNCTION growth.youtube_begin_authorization(uuid,text[]) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.youtube_begin_authorization(uuid,text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.youtube_begin_authorization(uuid,text[]) TO app_runtime;

COMMIT;
