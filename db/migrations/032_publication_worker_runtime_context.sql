-- Growth OS — worker tenant context and job completion boundary.
-- A worker may act only through a leased job carrying an explicit service
-- principal and workspace. User sessions remain the normal API context.
\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.tenant_context_valid(p_workspace_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $context$
  SELECT
    (
      growth.current_app_user_id() IS NOT NULL
      AND p_workspace_id = growth.current_workspace_id()
      AND EXISTS (
        SELECT 1
        FROM growth.memberships m
        WHERE m.workspace_id = p_workspace_id
          AND m.user_id = growth.current_app_user_id()
          AND m.status = 'active'
      )
    )
    OR
    (
      NULLIF(current_setting('app.service_principal_id', true), '') IS NOT NULL
      AND NULLIF(current_setting('app.job_id', true), '') IS NOT NULL
      AND p_workspace_id = growth.current_workspace_id()
      AND EXISTS (
        SELECT 1
        FROM growth.worker_service_principals sp
        WHERE sp.id = NULLIF(current_setting('app.service_principal_id', true), '')::uuid
          AND sp.status = 'active'
          AND sp.revoked_at IS NULL
          AND 'publication_intent' = ANY(sp.allowed_job_types)
      )
      AND EXISTS (
        SELECT 1
        FROM growth.jobs j
        WHERE j.id = NULLIF(current_setting('app.job_id', true), '')::uuid
          AND j.workspace_id = p_workspace_id
          AND j.service_principal_id = NULLIF(current_setting('app.service_principal_id', true), '')::uuid
          AND j.job_type = 'publication_intent'
          AND j.state = 'leased'
          AND j.leased_until IS NOT NULL
          AND j.leased_until > now()
      )
    );
$context$;

ALTER FUNCTION growth.tenant_context_valid(uuid)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.tenant_context_valid(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.tenant_context_valid(uuid) TO app_runtime, growth_worker;

CREATE OR REPLACE FUNCTION growth.complete_publication_job(
  p_service_principal_id uuid,
  p_job_id uuid,
  p_state text,
  p_available_at timestamptz,
  p_error_class text
)
RETURNS growth.jobs
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $complete$
DECLARE
  v_job growth.jobs;
  v_available_at timestamptz := COALESCE(p_available_at, now());
  v_safe_error_class text := NULLIF(
    left(regexp_replace(COALESCE(p_error_class, ''), '[^a-zA-Z0-9_.-]', '', 'g'), 100),
    ''
  );
BEGIN
  IF p_service_principal_id IS NULL
     OR p_job_id IS NULL
     OR p_state NOT IN ('done','retry_wait','dead')
  THEN
    RAISE EXCEPTION 'publication job completion requires valid identifiers and state';
  END IF;

  IF p_state = 'retry_wait' AND v_available_at <= now() THEN
    RAISE EXCEPTION 'retry_wait job must have a future availability time';
  END IF;

  SELECT j.* INTO v_job
  FROM growth.jobs j
  WHERE j.id = p_job_id
    AND j.service_principal_id = p_service_principal_id
    AND j.job_type = 'publication_intent'
    AND j.state = 'leased'
    AND j.leased_until IS NOT NULL
    AND j.leased_until > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'publication job is not leased by this service principal';
  END IF;

  UPDATE growth.jobs
  SET state = p_state,
      available_at = CASE WHEN p_state = 'retry_wait' THEN v_available_at ELSE available_at END,
      leased_until = NULL,
      last_error_class = CASE WHEN p_state = 'done' THEN NULL ELSE v_safe_error_class END
  WHERE id = p_job_id
  RETURNING * INTO v_job;

  RETURN v_job;
END;
$complete$;

ALTER FUNCTION growth.complete_publication_job(uuid,uuid,text,timestamptz,text)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.complete_publication_job(uuid,uuid,text,timestamptz,text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.complete_publication_job(uuid,uuid,text,timestamptz,text)
  TO growth_worker;

COMMIT;
