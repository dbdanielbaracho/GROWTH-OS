-- Growth OS — publication intent claim boundary.
-- Claims are lease-protected and idempotent. No provider call occurs here.
-- Provider attempts remain immutable evidence and are persisted by a later
-- completion/finalization boundary after the external call.

\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

ALTER TABLE growth.publication_intents
  ADD COLUMN IF NOT EXISTS current_attempt_no integer,
  ADD COLUMN IF NOT EXISTS claim_token uuid,
  ADD COLUMN IF NOT EXISTS claimed_at timestamptz,
  ADD COLUMN IF NOT EXISTS claim_expires_at timestamptz;

ALTER TABLE growth.publication_intents
  DROP CONSTRAINT IF EXISTS publication_intents_current_attempt_no_check;

ALTER TABLE growth.publication_intents
  ADD CONSTRAINT publication_intents_current_attempt_no_check
  CHECK (current_attempt_no IS NULL OR current_attempt_no > 0);

CREATE INDEX IF NOT EXISTS publication_claim_recovery_idx
  ON growth.publication_intents(status, claim_expires_at, updated_at)
  WHERE status = 'sending';

CREATE OR REPLACE FUNCTION growth.claim_publication_intent(
  p_workspace_id uuid,
  p_publication_intent_id uuid,
  p_claim_token uuid,
  p_now timestamptz
)
RETURNS growth.publication_intents
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.publication_intents;
  v_social_account_id uuid;
  v_now timestamptz := COALESCE(p_now, now());
BEGIN
  IF p_workspace_id IS NULL
     OR p_publication_intent_id IS NULL
     OR p_claim_token IS NULL
  THEN
    RAISE EXCEPTION 'publication claim requires complete identifiers';
  END IF;

  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'publication claim requires active tenant context';
  END IF;

  SELECT pi.* INTO v_row
  FROM growth.publication_intents pi
  WHERE pi.workspace_id = p_workspace_id
    AND pi.id = p_publication_intent_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'publication intent not found or not visible in this tenant context';
  END IF;

  IF v_row.status IN ('confirmed','cancelled','superseded','needs_user_action') THEN
    RAISE EXCEPTION 'publication intent cannot be claimed from status %', v_row.status;
  END IF;

  IF v_row.scheduled_for IS NOT NULL AND v_row.scheduled_for > v_now THEN
    RAISE EXCEPTION 'publication intent is not due yet';
  END IF;

  IF v_row.status = 'sending'
     AND v_row.claim_token = p_claim_token
  THEN
    RETURN v_row;
  END IF;

  IF v_row.status = 'sending'
     AND v_row.claim_expires_at IS NOT NULL
     AND v_row.claim_expires_at > v_now
  THEN
    RAISE EXCEPTION 'publication intent is already claimed';
  END IF;

  IF v_row.status NOT IN ('ready','scheduled','queued','failed_retryable','retrying','sending') THEN
    RAISE EXCEPTION 'publication intent cannot be claimed from status %', v_row.status;
  END IF;

  SELECT sa.id INTO v_social_account_id
  FROM growth.social_accounts sa
  JOIN growth.platform_connections pc
    ON pc.workspace_id = sa.workspace_id
   AND pc.id = sa.platform_connection_id
  WHERE sa.workspace_id = p_workspace_id
    AND sa.id = v_row.social_account_id
    AND pc.state = 'connected'
  FOR UPDATE OF sa, pc;

  IF v_social_account_id IS NULL THEN
    RAISE EXCEPTION 'publication claim requires a connected social account';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM growth.content_versions cv
    JOIN growth.content_items ci
      ON ci.workspace_id = cv.workspace_id
     AND ci.id = cv.content_item_id
    WHERE cv.workspace_id = p_workspace_id
      AND cv.id = v_row.content_version_id
      AND ci.status = 'approved'
  ) THEN
    RAISE EXCEPTION 'publication claim requires approved content';
  END IF;

  UPDATE growth.publication_intents
  SET status = 'sending',
      current_attempt_no = COALESCE(current_attempt_no, 0) + 1,
      claim_token = p_claim_token,
      claimed_at = v_now,
      claim_expires_at = v_now + interval '10 minutes',
      updated_at = v_now
  WHERE workspace_id = p_workspace_id
    AND id = p_publication_intent_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

ALTER FUNCTION growth.claim_publication_intent(uuid,uuid,uuid,timestamptz)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.claim_publication_intent(uuid,uuid,uuid,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.claim_publication_intent(uuid,uuid,uuid,timestamptz) TO app_runtime;

COMMIT;
