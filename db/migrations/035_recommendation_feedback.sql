-- Growth OS — deterministic recommendation storage and feedback.
-- Forward-only migration 035.
-- Recommendations are structured actions derived from stored opportunity evidence.
-- No text generation, synthetic evidence, or autonomous execution is introduced.

BEGIN;
SET search_path = growth, public;

CREATE TABLE growth.recommendations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  opportunity_id uuid NOT NULL,
  action_code text NOT NULL CHECK (action_code IN ('draft_content','review_evidence','plan_experiment')),
  status text NOT NULL DEFAULT 'proposed'
    CHECK (status IN ('proposed','accepted','dismissed','completed')),
  rationale jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, opportunity_id, action_code),
  FOREIGN KEY (workspace_id, opportunity_id)
    REFERENCES growth.opportunities(workspace_id, id)
);

CREATE TABLE growth.recommendation_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  recommendation_id uuid NOT NULL,
  feedback text NOT NULL CHECK (feedback IN ('accepted','dismissed','completed','irrelevant')),
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (workspace_id, recommendation_id)
    REFERENCES growth.recommendations(workspace_id, id),
  CONSTRAINT recommendation_feedback_note_length
    CHECK (note IS NULL OR char_length(note) <= 1000)
);

ALTER TABLE growth.recommendations ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.recommendations FORCE ROW LEVEL SECURITY;
CREATE POLICY recommendations_workspace_isolation
  ON growth.recommendations
  USING (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
  )
  WITH CHECK (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
  );

ALTER TABLE growth.recommendation_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.recommendation_feedback FORCE ROW LEVEL SECURITY;
CREATE POLICY recommendation_feedback_workspace_isolation
  ON growth.recommendation_feedback
  USING (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
  )
  WITH CHECK (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
  );

CREATE INDEX recommendations_workspace_status_idx
  ON growth.recommendations(workspace_id, status, updated_at DESC);
CREATE INDEX recommendations_opportunity_idx
  ON growth.recommendations(workspace_id, opportunity_id, created_at DESC);
CREATE INDEX recommendation_feedback_recommendation_idx
  ON growth.recommendation_feedback(workspace_id, recommendation_id, created_at DESC);

ALTER TABLE growth.recommendations OWNER TO growth_migrator;
ALTER TABLE growth.recommendation_feedback OWNER TO growth_migrator;
REVOKE ALL ON TABLE growth.recommendations FROM PUBLIC;
REVOKE ALL ON TABLE growth.recommendations FROM app_runtime;
REVOKE ALL ON TABLE growth.recommendation_feedback FROM PUBLIC;
REVOKE ALL ON TABLE growth.recommendation_feedback FROM app_runtime;

CREATE OR REPLACE FUNCTION growth.list_recommendations(
  p_workspace_id uuid,
  p_opportunity_id uuid,
  p_limit integer
)
RETURNS TABLE (
  id uuid,
  opportunity_id uuid,
  action_code text,
  status text,
  rationale jsonb,
  feedback_count bigint,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'recommendation workspace context mismatch';
  END IF;

  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'recommendation limit out of range';
  END IF;

  RETURN QUERY
  SELECT r.id,
         r.opportunity_id,
         r.action_code,
         r.status,
         r.rationale,
         count(f.id)::bigint AS feedback_count,
         r.created_at,
         r.updated_at
    FROM growth.recommendations r
    LEFT JOIN growth.recommendation_feedback f
      ON f.workspace_id = r.workspace_id
     AND f.recommendation_id = r.id
   WHERE r.workspace_id = p_workspace_id
     AND (p_opportunity_id IS NULL OR r.opportunity_id = p_opportunity_id)
   GROUP BY r.id
   ORDER BY CASE r.status
              WHEN 'proposed' THEN 1
              WHEN 'accepted' THEN 2
              WHEN 'completed' THEN 3
              ELSE 4
            END,
            r.updated_at DESC,
            r.id
   LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION growth.create_recommendation(
  p_workspace_id uuid,
  p_opportunity_id uuid,
  p_action_code text
)
RETURNS TABLE (
  id uuid,
  opportunity_id uuid,
  action_code text,
  status text,
  rationale jsonb,
  feedback_count bigint,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_evidence_count bigint;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'recommendation workspace context mismatch';
  END IF;

  IF p_action_code NOT IN ('draft_content','review_evidence','plan_experiment') THEN
    RAISE EXCEPTION 'unsupported recommendation action';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM growth.opportunities o
     WHERE o.workspace_id = p_workspace_id
       AND o.id = p_opportunity_id
       AND (o.expires_at IS NULL OR o.expires_at > now())
  ) THEN
    RAISE EXCEPTION 'opportunity is not available';
  END IF;

  SELECT count(*)::bigint
    INTO v_evidence_count
    FROM growth.opportunity_evidence oe
   WHERE oe.workspace_id = p_workspace_id
     AND oe.opportunity_id = p_opportunity_id;

  IF v_evidence_count < 1 THEN
    RAISE EXCEPTION 'recommendation requires stored opportunity evidence';
  END IF;

  INSERT INTO growth.recommendations (
    workspace_id, opportunity_id, action_code, status, rationale, updated_at
  ) VALUES (
    p_workspace_id,
    p_opportunity_id,
    p_action_code,
    'proposed',
    jsonb_build_object(
      'source', 'opportunity_radar',
      'rule_version', 'recommendation.action.v1',
      'evidence_count', v_evidence_count,
      'unsupported_inference', false,
      'autonomous_execution', false
    ),
    now()
  )
  ON CONFLICT (workspace_id, opportunity_id, action_code) DO UPDATE SET
    rationale = EXCLUDED.rationale,
    updated_at = now()
  RETURNING growth.recommendations.id INTO id;

  SELECT r.opportunity_id, r.action_code, r.status, r.rationale, r.created_at, r.updated_at
    INTO opportunity_id, action_code, status, rationale, created_at, updated_at
    FROM growth.recommendations r
   WHERE r.workspace_id = p_workspace_id
     AND r.id = id;

  SELECT count(*)::bigint
    INTO feedback_count
    FROM growth.recommendation_feedback f
   WHERE f.workspace_id = p_workspace_id
     AND f.recommendation_id = id;

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION growth.record_recommendation_feedback(
  p_workspace_id uuid,
  p_recommendation_id uuid,
  p_feedback text,
  p_note text
)
RETURNS TABLE (
  id uuid,
  recommendation_id uuid,
  feedback text,
  note text,
  created_at timestamptz,
  recommendation_status text
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_status text;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'recommendation workspace context mismatch';
  END IF;

  IF p_feedback NOT IN ('accepted','dismissed','completed','irrelevant') THEN
    RAISE EXCEPTION 'unsupported recommendation feedback';
  END IF;

  IF p_note IS NOT NULL AND char_length(p_note) > 1000 THEN
    RAISE EXCEPTION 'recommendation feedback note is too long';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM growth.recommendations r
     WHERE r.workspace_id = p_workspace_id
       AND r.id = p_recommendation_id
  ) THEN
    RAISE EXCEPTION 'recommendation is not available';
  END IF;

  v_status := CASE p_feedback
    WHEN 'accepted' THEN 'accepted'
    WHEN 'completed' THEN 'completed'
    WHEN 'dismissed' THEN 'dismissed'
    ELSE 'dismissed'
  END;

  INSERT INTO growth.recommendation_feedback (
    workspace_id, recommendation_id, feedback, note
  ) VALUES (
    p_workspace_id, p_recommendation_id, p_feedback, nullif(trim(p_note), '')
  )
  RETURNING recommendation_feedback.id,
            recommendation_feedback.recommendation_id,
            recommendation_feedback.feedback,
            recommendation_feedback.note,
            recommendation_feedback.created_at
       INTO id, recommendation_id, feedback, note, created_at;

  UPDATE growth.recommendations
     SET status = v_status,
         updated_at = now()
   WHERE workspace_id = p_workspace_id
     AND growth.recommendations.id = p_recommendation_id;

  recommendation_status := v_status;
  RETURN NEXT;
END;
$$;

ALTER FUNCTION growth.list_recommendations(uuid,uuid,integer) OWNER TO growth_migrator;
ALTER FUNCTION growth.create_recommendation(uuid,uuid,text) OWNER TO growth_migrator;
ALTER FUNCTION growth.record_recommendation_feedback(uuid,uuid,text,text) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.list_recommendations(uuid,uuid,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.create_recommendation(uuid,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.record_recommendation_feedback(uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.list_recommendations(uuid,uuid,integer) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.create_recommendation(uuid,uuid,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.record_recommendation_feedback(uuid,uuid,text,text) TO app_runtime;

COMMIT;
