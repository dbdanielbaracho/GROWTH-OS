-- Growth OS — feed evidence-backed experiment learning into the next recommendation.
-- Forward-only migration 064.

BEGIN;
SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.opportunity_learning_context(
  p_workspace_id uuid,
  p_opportunity_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_completed_experiments bigint;
  v_winner_count bigint;
  v_accepted_count bigint;
  v_completed_recommendation_count bigint;
  v_dismissed_count bigint;
  v_irrelevant_count bigint;
  v_latest_winner jsonb;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'learning workspace context mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM growth.opportunities o
     WHERE o.workspace_id = p_workspace_id
       AND o.id = p_opportunity_id
  ) THEN
    RAISE EXCEPTION 'learning opportunity is not available';
  END IF;

  SELECT count(DISTINCT e.id) FILTER (WHERE e.status = 'completed'),
         count(f.id) FILTER (WHERE f.outcome = 'winner')
    INTO v_completed_experiments, v_winner_count
    FROM growth.experiments e
    LEFT JOIN growth.experiment_feedback f
      ON f.workspace_id = e.workspace_id
     AND f.experiment_id = e.id
   WHERE e.workspace_id = p_workspace_id
     AND e.eligibility_rule->>'source_opportunity_id' = p_opportunity_id::text;

  SELECT count(*) FILTER (WHERE f.feedback = 'accepted'),
         count(*) FILTER (WHERE f.feedback = 'completed'),
         count(*) FILTER (WHERE f.feedback = 'dismissed'),
         count(*) FILTER (WHERE f.feedback = 'irrelevant')
    INTO v_accepted_count,
         v_completed_recommendation_count,
         v_dismissed_count,
         v_irrelevant_count
    FROM growth.recommendation_feedback f
    JOIN growth.recommendations r
      ON r.workspace_id = f.workspace_id
     AND r.id = f.recommendation_id
   WHERE r.workspace_id = p_workspace_id
     AND r.opportunity_id = p_opportunity_id;

  SELECT jsonb_build_object(
           'experiment_id', e.id,
           'variant_id', v.id,
           'label', v.label,
           'evidence_ref', f.evidence_ref,
           'recorded_at', f.created_at
         )
    INTO v_latest_winner
    FROM growth.experiment_feedback f
    JOIN growth.experiments e
      ON e.workspace_id = f.workspace_id
     AND e.id = f.experiment_id
    JOIN growth.experiment_variant_plans v
      ON v.workspace_id = f.workspace_id
     AND v.id = f.variant_plan_id
   WHERE f.workspace_id = p_workspace_id
     AND e.eligibility_rule->>'source_opportunity_id' = p_opportunity_id::text
     AND f.outcome = 'winner'
     AND f.evidence_ref IS NOT NULL
   ORDER BY f.created_at DESC, f.id DESC
   LIMIT 1;

  RETURN jsonb_build_object(
    'rule_version', 'opportunity.learning.v1',
    'completed_experiment_count', coalesce(v_completed_experiments, 0),
    'winner_count', coalesce(v_winner_count, 0),
    'recommendation_feedback', jsonb_build_object(
      'accepted', coalesce(v_accepted_count, 0),
      'completed', coalesce(v_completed_recommendation_count, 0),
      'dismissed', coalesce(v_dismissed_count, 0),
      'irrelevant', coalesce(v_irrelevant_count, 0)
    ),
    'latest_winner', v_latest_winner
  );
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
  v_learning jsonb;
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

  v_learning := growth.opportunity_learning_context(p_workspace_id, p_opportunity_id);

  INSERT INTO growth.recommendations (
    workspace_id, opportunity_id, action_code, status, rationale, updated_at
  ) VALUES (
    p_workspace_id,
    p_opportunity_id,
    p_action_code,
    'proposed',
    jsonb_build_object(
      'source', 'opportunity_radar',
      'rule_version', 'recommendation.action.v2',
      'evidence_count', v_evidence_count,
      'learning', v_learning,
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

CREATE OR REPLACE FUNCTION growth.record_experiment_feedback(
  p_workspace_id uuid,
  p_experiment_id uuid,
  p_variant_id uuid,
  p_outcome text,
  p_evidence_ref text,
  p_note text
)
RETURNS TABLE (
  id uuid,
  experiment_id uuid,
  variant_id uuid,
  outcome text,
  evidence_ref text,
  note text,
  created_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_opportunity_id uuid;
  v_learning jsonb;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'experiment workspace context mismatch';
  END IF;
  IF p_outcome NOT IN ('winner','loser','inconclusive') THEN
    RAISE EXCEPTION 'experiment outcome is invalid';
  END IF;
  IF p_outcome <> 'inconclusive'
     AND (p_evidence_ref IS NULL OR char_length(trim(p_evidence_ref)) NOT BETWEEN 1 AND 1000)
  THEN
    RAISE EXCEPTION 'experiment outcome requires stored evidence reference';
  END IF;
  IF NOT EXISTS (
    SELECT 1
      FROM growth.experiment_variant_plans v
     WHERE v.workspace_id = p_workspace_id
       AND v.id = p_variant_id
       AND v.experiment_id = p_experiment_id
  ) THEN
    RAISE EXCEPTION 'experiment variant is not available';
  END IF;

  SELECT nullif(e.eligibility_rule->>'source_opportunity_id','')::uuid
    INTO v_opportunity_id
    FROM growth.experiments e
   WHERE e.workspace_id = p_workspace_id
     AND e.id = p_experiment_id;

  UPDATE growth.experiment_variant_plans
     SET status = CASE p_outcome
       WHEN 'winner' THEN 'winner'
       WHEN 'loser' THEN 'loser'
       ELSE 'active'
     END
   WHERE workspace_id = p_workspace_id
     AND experiment_variant_plans.id = p_variant_id;

  UPDATE growth.experiments
     SET status = CASE WHEN p_outcome = 'winner' THEN 'completed' ELSE 'running' END,
         started_at = coalesce(started_at, now()),
         ended_at = CASE WHEN p_outcome = 'winner' THEN now() ELSE NULL END
   WHERE workspace_id = p_workspace_id
     AND experiments.id = p_experiment_id;

  INSERT INTO growth.experiment_feedback (
    workspace_id, experiment_id, variant_plan_id, outcome, evidence_ref, note
  ) VALUES (
    p_workspace_id, p_experiment_id, p_variant_id, p_outcome,
    nullif(trim(p_evidence_ref), ''), nullif(trim(p_note), '')
  )
  RETURNING experiment_feedback.id,
            experiment_feedback.experiment_id,
            experiment_feedback.variant_plan_id,
            experiment_feedback.outcome,
            experiment_feedback.evidence_ref,
            experiment_feedback.note,
            experiment_feedback.created_at
       INTO id, experiment_id, variant_id, outcome, evidence_ref, note, created_at;

  IF v_opportunity_id IS NOT NULL THEN
    v_learning := growth.opportunity_learning_context(p_workspace_id, v_opportunity_id);
    UPDATE growth.recommendations r
       SET rationale = jsonb_set(
             jsonb_set(
               coalesce(r.rationale, '{}'::jsonb),
               '{rule_version}',
               to_jsonb('recommendation.action.v2'::text),
               true
             ),
             '{learning}',
             v_learning,
             true
           ),
           updated_at = now()
     WHERE r.workspace_id = p_workspace_id
       AND r.opportunity_id = v_opportunity_id;
  END IF;

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
AS $
DECLARE
  v_status text;
  v_opportunity_id uuid;
  v_learning jsonb;
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

  SELECT r.opportunity_id
    INTO v_opportunity_id
    FROM growth.recommendations r
   WHERE r.workspace_id = p_workspace_id
     AND r.id = p_recommendation_id;

  IF NOT FOUND THEN
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

  v_learning := growth.opportunity_learning_context(p_workspace_id, v_opportunity_id);

  UPDATE growth.recommendations r
     SET status = v_status,
         rationale = jsonb_set(
           jsonb_set(
             coalesce(r.rationale, '{}'::jsonb),
             '{rule_version}',
             to_jsonb('recommendation.action.v2'::text),
             true
           ),
           '{learning}',
           v_learning,
           true
         ),
         updated_at = now()
   WHERE r.workspace_id = p_workspace_id
     AND r.id = p_recommendation_id;

  recommendation_status := v_status;
  RETURN NEXT;
END;
$;

ALTER FUNCTION growth.opportunity_learning_context(uuid,uuid) OWNER TO growth_migrator;
ALTER FUNCTION growth.create_recommendation(uuid,uuid,text) OWNER TO growth_migrator;
ALTER FUNCTION growth.record_recommendation_feedback(uuid,uuid,text,text) OWNER TO growth_migrator;
ALTER FUNCTION growth.record_experiment_feedback(uuid,uuid,uuid,text,text,text) OWNER TO growth_migrator;

REVOKE ALL ON FUNCTION growth.opportunity_learning_context(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.opportunity_learning_context(uuid,uuid) FROM app_runtime;
REVOKE ALL ON FUNCTION growth.create_recommendation(uuid,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.record_recommendation_feedback(uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.record_experiment_feedback(uuid,uuid,uuid,text,text,text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION growth.create_recommendation(uuid,uuid,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.record_recommendation_feedback(uuid,uuid,text,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.record_experiment_feedback(uuid,uuid,uuid,text,text,text) TO app_runtime;

COMMIT;
