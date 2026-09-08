-- Growth OS — auditable publication result finalization.
-- Persists one immutable provider attempt and closes the active claim.
-- This boundary performs no provider call.

\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.finalize_publication_intent(
  p_workspace_id uuid,
  p_publication_intent_id uuid,
  p_claim_token uuid,
  p_attempt_no integer,
  p_request_hash text,
  p_outcome text,
  p_http_status integer,
  p_provider_request_id text,
  p_provider_content_id text,
  p_provider_permalink text,
  p_started_at timestamptz,
  p_provider_responded_at timestamptz,
  p_raw_payload_ref text
)
RETURNS growth.publication_intents
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.publication_intents;
  v_existing growth.publication_attempts;
  v_now timestamptz := now();
  v_final_status text;
BEGIN
  IF p_workspace_id IS NULL
     OR p_publication_intent_id IS NULL
     OR p_claim_token IS NULL
     OR p_attempt_no IS NULL
     OR p_attempt_no <= 0
     OR p_request_hash IS NULL
     OR length(btrim(p_request_hash)) = 0
     OR p_outcome IS NULL
  THEN
    RAISE EXCEPTION 'publication finalization requires complete identifiers';
  END IF;

  IF p_outcome NOT IN ('confirmed','failed_retryable','needs_user_action') THEN
    RAISE EXCEPTION 'unsupported publication outcome %', p_outcome;
  END IF;

  IF p_http_status IS NOT NULL AND (p_http_status < 100 OR p_http_status > 599) THEN
    RAISE EXCEPTION 'invalid provider HTTP status';
  END IF;

  IF p_outcome = 'confirmed'
     AND (p_provider_content_id IS NULL OR length(btrim(p_provider_content_id)) = 0)
  THEN
    RAISE EXCEPTION 'confirmed publication requires provider content id';
  END IF;

  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'publication finalization requires active tenant context';
  END IF;

  SELECT pi.* INTO v_row
  FROM growth.publication_intents pi
  WHERE pi.workspace_id = p_workspace_id
    AND pi.id = p_publication_intent_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'publication intent not found or not visible in this tenant context';
  END IF;

  SELECT pa.* INTO v_existing
  FROM growth.publication_attempts pa
  WHERE pa.workspace_id = p_workspace_id
    AND pa.publication_intent_id = p_publication_intent_id
    AND pa.attempt_no = p_attempt_no;

  IF FOUND THEN
    IF v_existing.request_hash IS DISTINCT FROM p_request_hash
       OR v_existing.result_class IS DISTINCT FROM p_outcome
       OR v_existing.http_status IS DISTINCT FROM p_http_status
       OR v_existing.provider_request_id IS DISTINCT FROM p_provider_request_id
       OR v_existing.provider_content_id IS DISTINCT FROM p_provider_content_id
       OR v_existing.raw_payload_ref IS DISTINCT FROM p_raw_payload_ref
    THEN
      RAISE EXCEPTION 'publication attempt replay conflicts with immutable evidence';
    END IF;
    RETURN v_row;
  END IF;

  IF v_row.status IS DISTINCT FROM 'sending'
     OR v_row.claim_token IS DISTINCT FROM p_claim_token
     OR v_row.current_attempt_no IS DISTINCT FROM p_attempt_no
  THEN
    RAISE EXCEPTION 'publication intent claim is not active for this attempt';
  END IF;

  IF v_row.claim_expires_at IS NOT NULL AND v_row.claim_expires_at <= v_now THEN
    RAISE EXCEPTION 'publication intent claim has expired';
  END IF;

  v_final_status := p_outcome;

  INSERT INTO growth.publication_attempts(
    id, workspace_id, publication_intent_id, attempt_no, request_hash,
    provider_request_id, result_class, http_status, provider_content_id,
    started_at, provider_responded_at, persisted_at, raw_payload_ref
  )
  VALUES (
    gen_random_uuid(), p_workspace_id, p_publication_intent_id, p_attempt_no,
    p_request_hash, p_provider_request_id, p_outcome, p_http_status,
    p_provider_content_id, COALESCE(p_started_at, v_row.claimed_at, v_now),
    p_provider_responded_at, v_now, p_raw_payload_ref
  );

  UPDATE growth.publication_intents
  SET status = v_final_status,
      provider_content_id = CASE
        WHEN p_provider_content_id IS NULL THEN provider_content_id
        ELSE p_provider_content_id
      END,
      provider_permalink = CASE
        WHEN p_provider_permalink IS NULL THEN provider_permalink
        ELSE p_provider_permalink
      END,
      claim_token = NULL,
      claimed_at = NULL,
      claim_expires_at = NULL,
      updated_at = v_now
  WHERE workspace_id = p_workspace_id
    AND id = p_publication_intent_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

ALTER FUNCTION growth.finalize_publication_intent(
  uuid,uuid,uuid,integer,text,text,integer,text,text,text,timestamptz,timestamptz,text
) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.finalize_publication_intent(
  uuid,uuid,uuid,integer,text,text,integer,text,text,text,timestamptz,timestamptz,text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.finalize_publication_intent(
  uuid,uuid,uuid,integer,text,text,integer,text,text,text,timestamptz,timestamptz,text
) TO app_runtime;

COMMIT;
