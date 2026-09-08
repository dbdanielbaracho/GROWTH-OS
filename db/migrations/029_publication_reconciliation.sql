-- Growth OS — bounded publication reconciliation evidence.
-- Records provider-side ambiguity without storing raw provider payloads.

\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.record_publication_reconciliation(
  p_workspace_id uuid,
  p_publication_intent_id uuid,
  p_attempt_no integer,
  p_method text,
  p_confidence text,
  p_reconciliation_status text,
  p_candidate_provider_content_id text,
  p_evidence_ref text
)
RETURNS growth.publication_reconciliation_attempts
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.publication_reconciliation_attempts;
  v_intent growth.publication_intents;
  v_evidence_ref text := NULLIF(
    left(regexp_replace(COALESCE(p_evidence_ref, ''), '[^a-zA-Z0-9:/._-]', '', 'g'), 500),
    ''
  );
BEGIN
  IF p_workspace_id IS NULL
     OR p_publication_intent_id IS NULL
     OR p_attempt_no IS NULL
     OR p_attempt_no <= 0
  THEN
    RAISE EXCEPTION 'publication reconciliation requires complete identifiers';
  END IF;

  IF p_method NOT IN ('exact','resumable_status','fuzzy_recent_content','manual')
     OR p_confidence NOT IN ('exact','high','medium','low','none')
     OR p_reconciliation_status NOT IN ('pending','matched','not_found','ambiguous','escalated')
  THEN
    RAISE EXCEPTION 'publication reconciliation classification is invalid';
  END IF;

  IF p_reconciliation_status = 'matched'
     AND (p_confidence NOT IN ('exact','high')
          OR p_candidate_provider_content_id IS NULL
          OR length(btrim(p_candidate_provider_content_id)) = 0)
  THEN
    RAISE EXCEPTION 'matched reconciliation requires strong confidence and provider content id';
  END IF;

  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'publication reconciliation requires active tenant context';
  END IF;

  SELECT pi.* INTO v_intent
  FROM growth.publication_intents pi
  WHERE pi.workspace_id = p_workspace_id
    AND pi.id = p_publication_intent_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'publication intent not found or not visible in this tenant context';
  END IF;

  SELECT pra.* INTO v_row
  FROM growth.publication_reconciliation_attempts pra
  WHERE pra.workspace_id = p_workspace_id
    AND pra.publication_intent_id = p_publication_intent_id
    AND pra.attempt_no = p_attempt_no
  FOR UPDATE;

  IF FOUND THEN
    IF v_row.method IS DISTINCT FROM p_method
       OR v_row.confidence IS DISTINCT FROM p_confidence
       OR v_row.reconciliation_status IS DISTINCT FROM p_reconciliation_status
       OR v_row.candidate_provider_content_id IS DISTINCT FROM p_candidate_provider_content_id
    THEN
      RAISE EXCEPTION 'publication reconciliation replay conflicts with immutable evidence';
    END IF;
  ELSE
    INSERT INTO growth.publication_reconciliation_attempts(
      id, workspace_id, publication_intent_id, attempt_no, method,
      confidence, reconciliation_status, candidate_provider_content_id, evidence
    )
    VALUES (
      gen_random_uuid(), p_workspace_id, p_publication_intent_id, p_attempt_no,
      p_method, p_confidence, p_reconciliation_status,
      NULLIF(left(btrim(p_candidate_provider_content_id), 500), ''),
      jsonb_build_object('evidence_ref', v_evidence_ref)
    )
    RETURNING * INTO v_row;
  END IF;

  IF p_reconciliation_status = 'matched'
     AND v_intent.status IS DISTINCT FROM 'confirmed'
  THEN
    UPDATE growth.publication_intents
    SET status = 'confirmed',
        provider_content_id = NULLIF(left(btrim(p_candidate_provider_content_id), 500), ''),
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        scheduled_for = NULL,
        updated_at = now()
    WHERE workspace_id = p_workspace_id
      AND id = p_publication_intent_id;
  ELSIF p_reconciliation_status IN ('ambiguous','escalated')
        AND v_intent.status IN ('failed_retryable','retrying')
  THEN
    UPDATE growth.publication_intents
    SET status = 'needs_user_action',
        scheduled_for = NULL,
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        updated_at = now()
    WHERE workspace_id = p_workspace_id
      AND id = p_publication_intent_id;
  END IF;

  RETURN v_row;
END;
$$;

ALTER FUNCTION growth.record_publication_reconciliation(
  uuid,uuid,integer,text,text,text,text,text
) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.record_publication_reconciliation(
  uuid,uuid,integer,text,text,text,text,text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.record_publication_reconciliation(
  uuid,uuid,integer,text,text,text,text,text
) TO app_runtime;

COMMIT;
