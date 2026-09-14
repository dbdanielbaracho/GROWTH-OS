-- Growth OS — safe user-facing publication queue status projection.
-- Exposes only bounded operational state required to explain retry/dead-letter
-- behavior. Payloads, leases and service-principal identifiers remain private.
\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.list_publication_intents_v2(
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
  cancelled_at timestamptz,
  queue_state text,
  queue_attempts integer,
  queue_available_at timestamptz,
  queue_last_error_class text
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
    pi.cancelled_at,
    j.state AS queue_state,
    j.attempts AS queue_attempts,
    j.available_at AS queue_available_at,
    j.last_error_class AS queue_last_error_class
  FROM growth.publication_intents pi
  LEFT JOIN growth.jobs j
    ON j.workspace_id = pi.workspace_id
   AND j.job_type = 'publication_intent'
   AND j.operation_key = pi.id::text
  WHERE pi.workspace_id = p_workspace_id
    AND growth.current_workspace_id() = p_workspace_id
    AND growth.tenant_context_valid(p_workspace_id)
  ORDER BY pi.updated_at DESC, pi.id DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 100));
$status$;

ALTER FUNCTION growth.list_publication_intents_v2(uuid,integer)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.list_publication_intents_v2(uuid,integer)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.list_publication_intents_v2(uuid,integer)
  TO app_runtime;

COMMIT;
