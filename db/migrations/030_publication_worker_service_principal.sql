-- Growth OS — explicit service principal and durable publication queue claim.
-- Worker jobs must carry an auditable system principal; no anonymous
-- cross-tenant execution is permitted.
\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

CREATE TABLE IF NOT EXISTS growth.worker_service_principals (
  id uuid PRIMARY KEY,
  name text NOT NULL,
  status text NOT NULL CHECK (status IN ('active','revoked')),
  allowed_job_types text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  CHECK (
    (status = 'active' AND revoked_at IS NULL)
    OR (status = 'revoked' AND revoked_at IS NOT NULL)
  )
);

ALTER TABLE growth.jobs
  ADD COLUMN IF NOT EXISTS service_principal_id uuid;

ALTER TABLE growth.jobs
  DROP CONSTRAINT IF EXISTS jobs_service_principal_fk;

ALTER TABLE growth.jobs
  ADD CONSTRAINT jobs_service_principal_fk
  FOREIGN KEY (service_principal_id)
  REFERENCES growth.worker_service_principals(id);

ALTER TABLE growth.jobs
  DROP CONSTRAINT IF EXISTS jobs_publication_requires_service_principal;

ALTER TABLE growth.jobs
  ADD CONSTRAINT jobs_publication_requires_service_principal
  CHECK (job_type <> 'publication_intent' OR service_principal_id IS NOT NULL);

CREATE INDEX IF NOT EXISTS jobs_publication_due_idx
  ON growth.jobs(service_principal_id, state, available_at, leased_until, id)
  WHERE job_type = 'publication_intent';

CREATE OR REPLACE FUNCTION growth.enqueue_publication_job(
  p_workspace_id uuid,
  p_publication_intent_id uuid,
  p_service_principal_id uuid,
  p_available_at timestamptz
)
RETURNS growth.jobs
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $enqueue$
DECLARE
  v_job growth.jobs;
  v_intent growth.publication_intents;
  v_available_at timestamptz := COALESCE(p_available_at, now());
BEGIN
  IF p_workspace_id IS NULL
     OR p_publication_intent_id IS NULL
     OR p_service_principal_id IS NULL
  THEN
    RAISE EXCEPTION 'publication enqueue requires complete identifiers';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM growth.worker_service_principals sp
    WHERE sp.id = p_service_principal_id
      AND sp.status = 'active'
      AND sp.revoked_at IS NULL
      AND 'publication_intent' = ANY(sp.allowed_job_types)
  ) THEN
    RAISE EXCEPTION 'publication enqueue requires an active authorized service principal';
  END IF;

  SELECT pi.* INTO v_intent
  FROM growth.publication_intents pi
  WHERE pi.workspace_id = p_workspace_id
    AND pi.id = p_publication_intent_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'publication intent not found or not visible in this workspace';
  END IF;

  IF v_intent.status NOT IN ('ready','scheduled','queued','failed_retryable','retrying') THEN
    RAISE EXCEPTION 'publication intent cannot be enqueued from status %', v_intent.status;
  END IF;

  IF v_intent.scheduled_for IS NOT NULL
     AND v_intent.scheduled_for > v_available_at
  THEN
    RAISE EXCEPTION 'publication intent is not due at the requested enqueue time';
  END IF;

  SELECT j.* INTO v_job
  FROM growth.jobs j
  WHERE j.workspace_id = p_workspace_id
    AND j.job_type = 'publication_intent'
    AND j.operation_key = p_publication_intent_id::text
  FOR UPDATE;

  IF FOUND THEN
    IF v_job.service_principal_id IS DISTINCT FROM p_service_principal_id THEN
      RAISE EXCEPTION 'publication job is bound to a different service principal';
    END IF;

    IF v_job.state IN ('done','dead') THEN
      RAISE EXCEPTION 'publication job cannot be re-enqueued from terminal state %', v_job.state;
    END IF;

    UPDATE growth.jobs
    SET available_at = LEAST(available_at, v_available_at),
        payload = jsonb_build_object('publication_intent_id', p_publication_intent_id),
        state = CASE WHEN state = 'leased' THEN state ELSE 'queued' END
    WHERE id = v_job.id
    RETURNING * INTO v_job;

    RETURN v_job;
  END IF;

  INSERT INTO growth.jobs(
    id, workspace_id, job_type, operation_key, payload, state,
    available_at, service_principal_id
  )
  VALUES(
    gen_random_uuid(),
    p_workspace_id,
    'publication_intent',
    p_publication_intent_id::text,
    jsonb_build_object('publication_intent_id', p_publication_intent_id),
    'queued',
    v_available_at,
    p_service_principal_id
  )
  RETURNING * INTO v_job;

  RETURN v_job;
END;
$enqueue$;

ALTER FUNCTION growth.enqueue_publication_job(uuid,uuid,uuid,timestamptz)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.enqueue_publication_job(uuid,uuid,uuid,timestamptz)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.enqueue_publication_job(uuid,uuid,uuid,timestamptz)
  TO growth_worker;

CREATE OR REPLACE FUNCTION growth.claim_due_publication_job(
  p_service_principal_id uuid,
  p_now timestamptz,
  p_lease_seconds integer
)
RETURNS SETOF growth.jobs
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $claim$
DECLARE
  v_job growth.jobs;
  v_now timestamptz := COALESCE(p_now, now());
  v_lease_seconds integer := COALESCE(p_lease_seconds, 300);
BEGIN
  IF p_service_principal_id IS NULL
     OR v_lease_seconds < 30
     OR v_lease_seconds > 900
  THEN
    RAISE EXCEPTION 'publication job claim requires a valid service principal and lease';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM growth.worker_service_principals sp
    WHERE sp.id = p_service_principal_id
      AND sp.status = 'active'
      AND sp.revoked_at IS NULL
      AND 'publication_intent' = ANY(sp.allowed_job_types)
  ) THEN
    RAISE EXCEPTION 'publication job claim requires an active authorized service principal';
  END IF;

  SELECT j.* INTO v_job
  FROM growth.jobs j
  WHERE j.service_principal_id = p_service_principal_id
    AND j.job_type = 'publication_intent'
    AND j.state IN ('queued','retry_wait')
    AND j.available_at <= v_now
    AND (j.leased_until IS NULL OR j.leased_until <= v_now)
  ORDER BY j.available_at ASC, j.id ASC
  FOR UPDATE SKIP LOCKED
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  UPDATE growth.jobs
  SET state = 'leased',
      leased_until = v_now + make_interval(secs => v_lease_seconds),
      attempts = attempts + 1
  WHERE id = v_job.id
  RETURNING * INTO v_job;

  RETURN NEXT v_job;
  RETURN;
END;
$claim$;

ALTER FUNCTION growth.claim_due_publication_job(uuid,timestamptz,integer)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.claim_due_publication_job(uuid,timestamptz,integer)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.claim_due_publication_job(uuid,timestamptz,integer)
  TO growth_worker;

COMMIT;
