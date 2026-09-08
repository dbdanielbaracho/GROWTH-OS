-- Growth OS — safe user-facing publication status projection.
-- The runtime receives status metadata only; credentials, payloads and leases
-- remain behind the publication execution boundary.
\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.list_publication_intents(
  p_workspace_id uuid,
  p_limit integer
)
RETURNS TABLE(
  id uuid,
  social_account_id uuid,
  content_version_id uuid,
  status text,
  scheduled_for timestamptz,
  current_attempt_no integer,
  retry_count integer,
  last_error_class text,
  provider_content_id text,
  provider_permalink text,
  created_at timestamptz,
  updated_at timestamptz,
  cancelled_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $status$
  SELECT
    pi.id,
    pi.social_account_id,
    pi.content_version_id,
    pi.status,
    pi.scheduled_for,
    pi.current_attempt_no,
    pi.retry_count,
    pi.last_error_class,
    pi.provider_content_id,
    pi.provider_permalink,
    pi.created_at,
    pi.updated_at,
    pi.cancelled_at
  FROM growth.publication_intents pi
  WHERE pi.workspace_id = p_workspace_id
    AND growth.current_workspace_id() = p_workspace_id
    AND growth.tenant_context_valid(p_workspace_id)
  ORDER BY pi.updated_at DESC, pi.id DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 100));
$status$;

ALTER FUNCTION growth.list_publication_intents(uuid,integer)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.list_publication_intents(uuid,integer)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.list_publication_intents(uuid,integer)
  TO app_runtime;

COMMIT;
