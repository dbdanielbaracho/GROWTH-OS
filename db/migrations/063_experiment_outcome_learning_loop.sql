-- Growth OS — persisted experiment variants and evidence-backed learning outcomes.
-- Forward-only migration 063.

BEGIN;
SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.list_experiment_variants(
  p_workspace_id uuid,
  p_experiment_id uuid
)
RETURNS TABLE (
  id uuid,
  experiment_id uuid,
  label text,
  lineage jsonb,
  status text,
  created_at timestamptz,
  latest_outcome text,
  latest_evidence_ref text,
  feedback_created_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'experiment workspace context mismatch';
  END IF;
  IF NOT EXISTS (
    SELECT 1
      FROM growth.experiments e
     WHERE e.workspace_id = p_workspace_id
       AND e.id = p_experiment_id
  ) THEN
    RAISE EXCEPTION 'experiment is not available';
  END IF;

  RETURN QUERY
  SELECT v.id,
         v.experiment_id,
         v.label,
         v.lineage,
         v.status,
         v.created_at,
         latest.outcome,
         latest.evidence_ref,
         latest.created_at
    FROM growth.experiment_variant_plans v
    LEFT JOIN LATERAL (
      SELECT f.outcome, f.evidence_ref, f.created_at
        FROM growth.experiment_feedback f
       WHERE f.workspace_id = v.workspace_id
         AND f.experiment_id = v.experiment_id
         AND f.variant_plan_id = v.id
       ORDER BY f.created_at DESC, f.id DESC
       LIMIT 1
    ) latest ON true
   WHERE v.workspace_id = p_workspace_id
     AND v.experiment_id = p_experiment_id
   ORDER BY v.created_at, v.id;
END;
$$;

CREATE OR REPLACE FUNCTION growth.add_experiment_variant(
  p_workspace_id uuid,
  p_experiment_id uuid,
  p_label text,
  p_lineage jsonb
)
RETURNS TABLE (
  id uuid,
  experiment_id uuid,
  label text,
  lineage jsonb,
  status text,
  created_at timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_opportunity_id uuid;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'experiment workspace context mismatch';
  END IF;
  IF p_label IS NULL OR char_length(trim(p_label)) NOT BETWEEN 1 AND 120
     OR p_lineage IS NULL OR jsonb_typeof(p_lineage) <> 'object'
  THEN
    RAISE EXCEPTION 'experiment variant fields are invalid';
  END IF;

  SELECT nullif(e.eligibility_rule->>'source_opportunity_id','')::uuid
    INTO v_opportunity_id
    FROM growth.experiments e
   WHERE e.workspace_id = p_workspace_id
     AND e.id = p_experiment_id
     AND e.status IN ('draft', 'running');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'experiment is not available for variant planning';
  END IF;
  IF v_opportunity_id IS NOT NULL
     AND (NOT (p_lineage ? 'source_opportunity_id')
       OR p_lineage->>'source_opportunity_id' <> v_opportunity_id::text)
  THEN
    RAISE EXCEPTION 'variant lineage must reference the experiment opportunity';
  END IF;

  RETURN QUERY
  INSERT INTO growth.experiment_variant_plans (
    workspace_id, experiment_id, label, lineage
  ) VALUES (
    p_workspace_id, p_experiment_id, trim(p_label), p_lineage
  )
  RETURNING experiment_variant_plans.id, experiment_variant_plans.experiment_id,
            experiment_variant_plans.label, experiment_variant_plans.lineage,
            experiment_variant_plans.status, experiment_variant_plans.created_at;

  UPDATE growth.experiments
     SET status = 'running',
         started_at = coalesce(started_at, now())
   WHERE workspace_id = p_workspace_id
     AND experiments.id = p_experiment_id
     AND status = 'draft';
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
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
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
    SELECT 1 FROM growth.experiment_variant_plans v
     WHERE v.workspace_id = p_workspace_id
       AND v.id = p_variant_id
       AND v.experiment_id = p_experiment_id
  ) THEN
    RAISE EXCEPTION 'experiment variant is not available';
  END IF;

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

  RETURN QUERY
  INSERT INTO growth.experiment_feedback (
    workspace_id, experiment_id, variant_plan_id, outcome, evidence_ref, note
  ) VALUES (
    p_workspace_id, p_experiment_id, p_variant_id, p_outcome,
    nullif(trim(p_evidence_ref), ''), nullif(trim(p_note), '')
  )
  RETURNING experiment_feedback.id, experiment_feedback.experiment_id,
            experiment_feedback.variant_plan_id, experiment_feedback.outcome,
            experiment_feedback.evidence_ref, experiment_feedback.note,
            experiment_feedback.created_at;
END;
$$;

ALTER FUNCTION growth.list_experiment_variants(uuid,uuid) OWNER TO growth_migrator;
ALTER FUNCTION growth.add_experiment_variant(uuid,uuid,text,jsonb) OWNER TO growth_migrator;
ALTER FUNCTION growth.record_experiment_feedback(uuid,uuid,uuid,text,text,text) OWNER TO growth_migrator;

REVOKE ALL ON FUNCTION growth.list_experiment_variants(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.add_experiment_variant(uuid,uuid,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.record_experiment_feedback(uuid,uuid,uuid,text,text,text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION growth.list_experiment_variants(uuid,uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.add_experiment_variant(uuid,uuid,text,jsonb) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.record_experiment_feedback(uuid,uuid,uuid,text,text,text) TO app_runtime;

COMMIT;
