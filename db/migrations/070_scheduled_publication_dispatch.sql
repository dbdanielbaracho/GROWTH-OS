-- Growth OS — scheduled publication creation and automatic due dispatch.
-- This migration closes the calendar -> durable queue boundary without
-- weakening the existing tenant or worker service-principal contracts.
\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.schedule_publication_intent(
  p_workspace_id uuid,
  p_publication_intent_id uuid,
  p_scheduled_for timestamptz
)
RETURNS growth.publication_intents
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $schedule$
DECLARE
  v_row growth.publication_intents;
BEGIN
  IF p_workspace_id IS NULL
     OR p_publication_intent_id IS NULL
     OR p_scheduled_for IS NULL
  THEN
    RAISE EXCEPTION 'publication scheduling requires complete identifiers';
  END IF;

  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'publication scheduling requires active tenant context';
  END IF;

  IF p_scheduled_for <= now() THEN
    RAISE EXCEPTION 'publication scheduling requires a future timestamp';
  END IF;

  SELECT pi.* INTO v_row
  FROM growth.publication_intents pi
  WHERE pi.workspace_id = p_workspace_id
    AND pi.id = p_publication_intent_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'publication intent not found or not visible in this tenant context';
  END IF;

  IF v_row.status = 'scheduled'
     AND v_row.scheduled_for IS NOT DISTINCT FROM p_scheduled_for
  THEN
    RETURN v_row;
  END IF;

  IF v_row.status IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'publication intent cannot be scheduled from status %', v_row.status;
  END IF;

  UPDATE growth.publication_intents
  SET status = 'scheduled',
      scheduled_for = p_scheduled_for,
      updated_at = now()
  WHERE workspace_id = p_workspace_id
    AND id = p_publication_intent_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$schedule$;

ALTER FUNCTION growth.schedule_publication_intent(uuid,uuid,timestamptz)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.schedule_publication_intent(uuid,uuid,timestamptz)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.schedule_publication_intent(uuid,uuid,timestamptz)
  TO app_runtime;

CREATE OR REPLACE FUNCTION growth.enqueue_due_scheduled_publications(
  p_service_principal_id uuid,
  p_now timestamptz,
  p_limit integer
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $dispatch$
DECLARE
  v_now timestamptz := COALESCE(p_now, now());
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100);
  v_intent record;
  v_enqueued integer := 0;
BEGIN
  IF p_service_principal_id IS NULL THEN
    RAISE EXCEPTION 'scheduled publication dispatch requires a service principal';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM growth.worker_service_principals sp
    WHERE sp.id = p_service_principal_id
      AND sp.status = 'active'
      AND sp.revoked_at IS NULL
      AND 'publication_intent' = ANY(sp.allowed_job_types)
  ) THEN
    RAISE EXCEPTION 'scheduled publication dispatch requires an active authorized service principal';
  END IF;

  FOR v_intent IN
    SELECT pi.workspace_id, pi.id, pi.scheduled_for
    FROM growth.publication_intents pi
    WHERE pi.status = 'scheduled'
      AND pi.scheduled_for IS NOT NULL
      AND pi.scheduled_for <= v_now
    ORDER BY pi.scheduled_for ASC, pi.id ASC
    FOR UPDATE SKIP LOCKED
    LIMIT v_limit
  LOOP
    PERFORM growth.enqueue_publication_job(
      v_intent.workspace_id,
      v_intent.id,
      p_service_principal_id,
      v_now
    );

    UPDATE growth.publication_intents
    SET status = 'queued',
        updated_at = v_now
    WHERE workspace_id = v_intent.workspace_id
      AND id = v_intent.id
      AND status = 'scheduled';

    IF FOUND THEN
      v_enqueued := v_enqueued + 1;
    END IF;
  END LOOP;

  RETURN v_enqueued;
END;
$dispatch$;

ALTER FUNCTION growth.enqueue_due_scheduled_publications(uuid,timestamptz,integer)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.enqueue_due_scheduled_publications(uuid,timestamptz,integer)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.enqueue_due_scheduled_publications(uuid,timestamptz,integer)
  TO growth_worker;

COMMIT;
