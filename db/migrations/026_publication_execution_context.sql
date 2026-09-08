-- Growth OS — provider-neutral publication execution context.
-- Exposes only the active claim's approved content, publishable asset and
-- encrypted provider credential through a narrow SECURITY DEFINER helper.

\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.get_publication_execution_context(
  p_workspace_id uuid,
  p_publication_intent_id uuid,
  p_claim_token uuid
)
RETURNS TABLE(
  publication_intent_id uuid,
  workspace_id uuid,
  connection_id uuid,
  claim_token uuid,
  attempt_no integer,
  provider text,
  social_account_id uuid,
  content_version_id uuid,
  body text,
  structure jsonb,
  media_asset_id uuid,
  storage_ref text,
  mime_type text,
  bytes bigint,
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
AS $context$
  SELECT
    pi.id,
    pi.workspace_id,
    pc.id,
    pi.claim_token,
    pi.current_attempt_no,
    pc.platform,
    pi.social_account_id,
    pi.content_version_id,
    cv.body,
    cv.structure_json,
    pi.media_asset_id,
    ma.storage_ref,
    ma.mime_type,
    ma.bytes,
    sa.provider_account_id,
    pcd.credential_ciphertext,
    pcd.cipher_version,
    pcd.key_version,
    pcd.token_expires_at,
    pcd.refresh_available,
    pc.granted_scopes
  FROM growth.publication_intents pi
  JOIN growth.content_versions cv
    ON cv.workspace_id = pi.workspace_id
   AND cv.id = pi.content_version_id
  JOIN growth.content_items ci
    ON ci.workspace_id = cv.workspace_id
   AND ci.id = cv.content_item_id
  JOIN growth.media_assets ma
    ON ma.workspace_id = pi.workspace_id
   AND ma.id = pi.media_asset_id
  JOIN growth.social_accounts sa
    ON sa.workspace_id = pi.workspace_id
   AND sa.id = pi.social_account_id
  JOIN growth.platform_connections pc
    ON pc.workspace_id = sa.workspace_id
   AND pc.id = sa.platform_connection_id
  JOIN growth.provider_credentials pcd
    ON pcd.workspace_id = pc.workspace_id
   AND pcd.platform_connection_id = pc.id
   AND pcd.provider = pc.platform
  JOIN growth.managed_accounts managed
    ON managed.workspace_id = pc.workspace_id
   AND managed.id = pc.managed_account_id
  WHERE pi.workspace_id = p_workspace_id
    AND pi.id = p_publication_intent_id
    AND pi.claim_token = p_claim_token
    AND pi.status = 'sending'
    AND pi.claim_expires_at IS NOT NULL
    AND pi.claim_expires_at > now()
    AND pi.media_asset_id IS NOT NULL
    AND ma.content_version_id = pi.content_version_id
    AND ma.purpose = 'publishable'
    AND ci.status = 'approved'
    AND pc.state = 'connected'
    AND managed.authority_status = 'contractually_granted'
    AND growth.current_workspace_id() = p_workspace_id
    AND growth.tenant_context_valid(p_workspace_id)
  LIMIT 1;
$context$;

ALTER FUNCTION growth.get_publication_execution_context(uuid,uuid,uuid)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.get_publication_execution_context(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.get_publication_execution_context(uuid,uuid,uuid) TO app_runtime;

COMMIT;
