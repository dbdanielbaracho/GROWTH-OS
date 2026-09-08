-- Growth OS — durable publication retry scheduling.
-- Requeues only a finalized retryable attempt; no provider call occurs here.

\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

ALTER TABLE growth.publication_intents
  ADD COLUMN IF NOT EXISTS retry_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_error_class text;

ALTER TABLE growth.publication_intents
  DROP CONSTRAINT IF EXISTS publication_intents_retry_count_check;

ALTER TABLE growth.publication_intents
  ADD CONSTRAINT publication_intents_retry_count_check
  CHECK (retry_count >= 0);

CREATE INDEX IF NOT EXISTS publication_retry_due_idx
  ON growth.publication_intents(status, scheduled_for, updated_at)
  WHERE status IN ('failed_retryable','retrying');

CREATE OR REPLACE FUNCTION growth.schedule_publication_retry(
  p_workspace_id uuid,
  p_publication_intent_id uuid,
  p_attempt_no integer,
  p_next_retry_at timestamptz,
  p_error_class text
)
RETURNS growth.publication_intents
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.publication_intents;
  v_next timestamptz := COALESCE(p_next_retry_at, now());
  v_safe_error_class text := NULLIF(
    left(regexp_replace(COALESCE(p_error_class, ''), '[^a-zA-Z0-9_.-]', '', 'g'), 100),
    ''
  );
BEGIN
  IF p_workspace_id IS NULL
     OR p_publication_intent_id IS NULL
     OR p_attempt_no IS NULL
     OR p_attempt_no <= 0
  THEN
    RAISE EXCEPTION 'publication retry requires complete identifiers';
  END IF;

  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'publication retry requires active tenant context';
  END IF;

  SELECT pi.* INTO v_row
  FROM growth.publication_intents pi
  WHERE pi.workspace_id = p_workspace_id
    AND pi.id = p_publication_intent_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'publication intent not found or not visible in this tenant context';
  END IF;

  IF v_row.current_attempt_no IS DISTINCT FROM p_attempt_no THEN
    RAISE EXCEPTION 'publication retry attempt does not match current attempt';
  END IF;

  IF v_row.status IS DISTINCT FROM 'failed_retryable' THEN
    RAISE EXCEPTION 'publication retry requires failed_retryable status';
  END IF;

  IF v_row.retry_count >= 5 THEN
    UPDATE growth.publication_intents
    SET status = 'needs_user_action',
        scheduled_for = NULL,
        last_error_class = v_safe_error_class,
        updated_at = now()
    WHERE workspace_id = p_workspace_id
      AND id = p_publication_intent_id
    RETURNING * INTO v_row;
    RETURN v_row;
  END IF;

  UPDATE growth.publication_intents
  SET status = 'retrying',
      retry_count = retry_count + 1,
      scheduled_for = v_next,
      last_error_class = v_safe_error_class,
      updated_at = now()
  WHERE workspace_id = p_workspace_id
    AND id = p_publication_intent_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

ALTER FUNCTION growth.schedule_publication_retry(uuid,uuid,integer,timestamptz,text)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.schedule_publication_retry(uuid,uuid,integer,timestamptz,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.schedule_publication_retry(uuid,uuid,integer,timestamptz,text) TO app_runtime;

COMMIT;
