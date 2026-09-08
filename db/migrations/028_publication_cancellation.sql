-- Growth OS — safe cancellation of publication intents.
-- Cancellation is local and never calls a provider.

\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

ALTER TABLE growth.publication_intents
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_by uuid REFERENCES growth.users(id);

CREATE OR REPLACE FUNCTION growth.cancel_publication_intent(
  p_workspace_id uuid,
  p_publication_intent_id uuid,
  p_actor_user_id uuid
)
RETURNS growth.publication_intents
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.publication_intents;
BEGIN
  IF p_workspace_id IS NULL
     OR p_publication_intent_id IS NULL
     OR p_actor_user_id IS NULL
  THEN
    RAISE EXCEPTION 'publication cancellation requires complete identifiers';
  END IF;

  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR current_setting('app.user_id', true)::uuid IS DISTINCT FROM p_actor_user_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'publication cancellation requires active actor context';
  END IF;

  SELECT pi.* INTO v_row
  FROM growth.publication_intents pi
  WHERE pi.workspace_id = p_workspace_id
    AND pi.id = p_publication_intent_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'publication intent not found or not visible in this tenant context';
  END IF;

  IF v_row.status IN ('sending','confirmed','cancelled','superseded') THEN
    RAISE EXCEPTION 'publication intent cannot be cancelled from status %', v_row.status;
  END IF;

  UPDATE growth.publication_intents
  SET status = 'cancelled',
      cancelled_at = now(),
      cancelled_by = p_actor_user_id,
      scheduled_for = NULL,
      claim_token = NULL,
      claimed_at = NULL,
      claim_expires_at = NULL,
      updated_at = now()
  WHERE workspace_id = p_workspace_id
    AND id = p_publication_intent_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

ALTER FUNCTION growth.cancel_publication_intent(uuid,uuid,uuid)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.cancel_publication_intent(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.cancel_publication_intent(uuid,uuid,uuid) TO app_runtime;

COMMIT;
