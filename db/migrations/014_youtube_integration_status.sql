-- Growth OS — YouTube integration status helper (Issue #26).
-- Forward-only. Preserves migrations 001-013 byte-for-byte.
--
-- Purpose:
-- expose only the minimum non-secret metadata the authenticated web UI needs
-- to connect/sync an authorized YouTube account, without granting app_runtime
-- direct SELECT on managed_accounts or platform_connections.

\set ON_ERROR_STOP on

BEGIN;
SET search_path = growth, public;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='growth_migrator') THEN
    RAISE EXCEPTION '014 requires growth_migrator role';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_runtime') THEN
    RAISE EXCEPTION '014 requires app_runtime role';
  END IF;
  IF has_table_privilege('app_runtime','growth.managed_accounts','SELECT') THEN
    RAISE EXCEPTION '014 refuses to widen an already-open managed_accounts boundary';
  END IF;
  IF has_table_privilege('app_runtime','growth.platform_connections','SELECT') THEN
    RAISE EXCEPTION '014 refuses to widen an already-open platform_connections boundary';
  END IF;
END $$;

CREATE FUNCTION growth.youtube_integration_status()
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
    ma.id AS managed_account_id,
    ma.owner_type,
    ma.authority_status,
    ma.contribution_eligibility,
    pc.id AS connection_id,
    pc.state AS connection_state,
    pc.updated_at AS connection_updated_at,
    sa.id AS social_account_id,
    sa.provider_account_id,
    sa.handle,
    sa.account_type,
    sa.market,
    sa.timezone AS source_timezone
  FROM growth.managed_accounts ma
  LEFT JOIN LATERAL (
    SELECT p.id,p.state,p.updated_at
    FROM growth.platform_connections p
    WHERE p.workspace_id=ma.workspace_id
      AND p.managed_account_id=ma.id
      AND p.platform='youtube'
    ORDER BY
      CASE p.state
        WHEN 'connected' THEN 0
        WHEN 'reauth_required' THEN 1
        WHEN 'degraded' THEN 2
        WHEN 'authorizing' THEN 3
        WHEN 'failed' THEN 4
        WHEN 'disconnected' THEN 5
        WHEN 'revoked' THEN 6
        ELSE 7
      END,
      p.updated_at DESC,
      p.id
    LIMIT 1
  ) pc ON true
  LEFT JOIN growth.social_accounts sa
    ON sa.workspace_id=ma.workspace_id
   AND sa.platform_connection_id=pc.id
   AND sa.platform='youtube'
  WHERE ma.workspace_id=growth.current_workspace_id()
    AND growth.tenant_context_valid(ma.workspace_id)
    AND ma.authority_status='contractually_granted'
  ORDER BY ma.created_at,ma.id;
$$;

ALTER FUNCTION growth.youtube_integration_status() OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.youtube_integration_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.youtube_integration_status() TO app_runtime;

COMMIT;
