-- Growth OS — experiment planning, variants and outcome lineage.
-- Forward-only migration 036.
-- This block stores plans and evidence-backed outcomes only. It does not publish.

BEGIN;
SET search_path = growth, public;

CREATE TABLE growth.experiments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  opportunity_id uuid,
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 160),
  hypothesis text NOT NULL CHECK (char_length(trim(hypothesis)) BETWEEN 1 AND 2000),
  decision_rule text NOT NULL CHECK (char_length(trim(decision_rule)) BETWEEN 1 AND 2000),
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','running','completed','archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, id),
  FOREIGN KEY (workspace_id, opportunity_id)
    REFERENCES growth.opportunities(workspace_id, id)
);

CREATE TABLE growth.experiment_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  experiment_id uuid NOT NULL,
  label text NOT NULL CHECK (char_length(trim(label)) BETWEEN 1 AND 120),
  lineage jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'candidate'
    CHECK (status IN ('candidate','active','winner','loser','archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, experiment_id, label),
  FOREIGN KEY (workspace_id, experiment_id)
    REFERENCES growth.experiments(workspace_id, id),
  CONSTRAINT experiment_variant_lineage_object
    CHECK (jsonb_typeof(lineage) = 'object')
);

CREATE TABLE growth.experiment_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  experiment_id uuid NOT NULL,
  variant_id uuid NOT NULL,
  outcome text NOT NULL CHECK (outcome IN ('winner','loser','inconclusive')),
  evidence_ref text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (workspace_id, experiment_id)
    REFERENCES growth.experiments(workspace_id, id),
  FOREIGN KEY (workspace_id, variant_id)
    REFERENCES growth.experiment_variants(workspace_id, id),
  CONSTRAINT experiment_feedback_evidence_required
    CHECK (
      outcome = 'inconclusive'
      OR (evidence_ref IS NOT NULL AND char_length(trim(evidence_ref)) BETWEEN 1 AND 1000)
    ),
  CONSTRAINT experiment_feedback_note_length
    CHECK (note IS NULL OR char_length(note) <= 1000)
);

ALTER TABLE growth.experiments ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.experiments FORCE ROW LEVEL SECURITY;
CREATE POLICY experiments_workspace_isolation ON growth.experiments
  USING (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id));

ALTER TABLE growth.experiment_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.experiment_variants FORCE ROW LEVEL SECURITY;
CREATE POLICY experiment_variants_workspace_isolation ON growth.experiment_variants
  USING (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id));

ALTER TABLE growth.experiment_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.experiment_feedback FORCE ROW LEVEL SECURITY;
CREATE POLICY experiment_feedback_workspace_isolation ON growth.experiment_feedback
  USING (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id));

CREATE INDEX experiments_workspace_status_idx ON growth.experiments(workspace_id, status, updated_at DESC);
CREATE INDEX experiment_variants_experiment_idx ON growth.experiment_variants(workspace_id, experiment_id, created_at);
CREATE INDEX experiment_feedback_variant_idx ON growth.experiment_feedback(workspace_id, variant_id, created_at DESC);

ALTER TABLE growth.experiments OWNER TO growth_migrator;
ALTER TABLE growth.experiment_variants OWNER TO growth_migrator;
ALTER TABLE growth.experiment_feedback OWNER TO growth_migrator;
REVOKE ALL ON TABLE growth.experiments FROM PUBLIC;
REVOKE ALL ON TABLE growth.experiments FROM app_runtime;
REVOKE ALL ON TABLE growth.experiment_variants FROM PUBLIC;
REVOKE ALL ON TABLE growth.experiment_variants FROM app_runtime;
REVOKE ALL ON TABLE growth.experiment_feedback FROM PUBLIC;
REVOKE ALL ON TABLE growth.experiment_feedback FROM app_runtime;

CREATE OR REPLACE FUNCTION growth.list_experiments(
  p_workspace_id uuid,
  p_limit integer
)
RETURNS TABLE (
  id uuid,
  opportunity_id uuid,
  name text,
  hypothesis text,
  decision_rule text,
  status text,
  variant_count bigint,
  created_at timestamptz,
  updated_at timestamptz
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
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'experiment limit out of range';
  END IF;

  RETURN QUERY
  SELECT e.id, e.opportunity_id, e.name, e.hypothesis, e.decision_rule, e.status,
         count(v.id)::bigint, e.created_at, e.updated_at
    FROM growth.experiments e
    LEFT JOIN growth.experiment_variants v
      ON v.workspace_id = e.workspace_id AND v.experiment_id = e.id
   WHERE e.workspace_id = p_workspace_id
   GROUP BY e.id
   ORDER BY e.updated_at DESC, e.id
   LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION growth.create_experiment(
  p_workspace_id uuid,
  p_opportunity_id uuid,
  p_name text,
  p_hypothesis text,
  p_decision_rule text
)
RETURNS TABLE (
  id uuid,
  opportunity_id uuid,
  name text,
  hypothesis text,
  decision_rule text,
  status text,
  created_at timestamptz,
  updated_at timestamptz
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
  IF p_name IS NULL OR char_length(trim(p_name)) NOT BETWEEN 1 AND 160
     OR p_hypothesis IS NULL OR char_length(trim(p_hypothesis)) NOT BETWEEN 1 AND 2000
     OR p_decision_rule IS NULL OR char_length(trim(p_decision_rule)) NOT BETWEEN 1 AND 2000
  THEN
    RAISE EXCEPTION 'experiment fields are invalid';
  END IF;
  IF p_opportunity_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM growth.opportunities o
     WHERE o.workspace_id = p_workspace_id
       AND o.id = p_opportunity_id
       AND (o.expires_at IS NULL OR o.expires_at > now())
  ) THEN
    RAISE EXCEPTION 'experiment opportunity is not available';
  END IF;
  IF p_opportunity_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM growth.opportunity_evidence oe
     WHERE oe.workspace_id = p_workspace_id AND oe.opportunity_id = p_opportunity_id
  ) THEN
    RAISE EXCEPTION 'experiment opportunity requires stored evidence';
  END IF;

  RETURN QUERY
  INSERT INTO growth.experiments (
    workspace_id, opportunity_id, name, hypothesis, decision_rule
  ) VALUES (
    p_workspace_id, p_opportunity_id, trim(p_name), trim(p_hypothesis), trim(p_decision_rule)
  )
  RETURNING experiments.id, experiments.opportunity_id, experiments.name,
            experiments.hypothesis, experiments.decision_rule, experiments.status,
            experiments.created_at, experiments.updated_at;
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

  SELECT e.opportunity_id INTO v_opportunity_id
    FROM growth.experiments e
   WHERE e.workspace_id = p_workspace_id
     AND e.id = p_experiment_id
     AND e.status = 'draft';

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
  INSERT INTO growth.experiment_variants (
    workspace_id, experiment_id, label, lineage
  ) VALUES (
    p_workspace_id, p_experiment_id, trim(p_label), p_lineage
  )
  RETURNING experiment_variants.id, experiment_variants.experiment_id,
            experiment_variants.label, experiment_variants.lineage,
            experiment_variants.status, experiment_variants.created_at;
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
    SELECT 1 FROM growth.experiment_variants v
     WHERE v.workspace_id = p_workspace_id
       AND v.id = p_variant_id
       AND v.experiment_id = p_experiment_id
  ) THEN
    RAISE EXCEPTION 'experiment variant is not available';
  END IF;

  RETURN QUERY
  INSERT INTO growth.experiment_feedback (
    workspace_id, experiment_id, variant_id, outcome, evidence_ref, note
  ) VALUES (
    p_workspace_id, p_experiment_id, p_variant_id, p_outcome,
    nullif(trim(p_evidence_ref), ''), nullif(trim(p_note), '')
  )
  RETURNING experiment_feedback.id, experiment_feedback.experiment_id,
            experiment_feedback.variant_id, experiment_feedback.outcome,
            experiment_feedback.evidence_ref, experiment_feedback.note,
            experiment_feedback.created_at;
END;
$$;

ALTER FUNCTION growth.list_experiments(uuid,integer) OWNER TO growth_migrator;
ALTER FUNCTION growth.create_experiment(uuid,uuid,text,text,text) OWNER TO growth_migrator;
ALTER FUNCTION growth.add_experiment_variant(uuid,uuid,text,jsonb) OWNER TO growth_migrator;
ALTER FUNCTION growth.record_experiment_feedback(uuid,uuid,uuid,text,text,text) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.list_experiments(uuid,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.create_experiment(uuid,uuid,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.add_experiment_variant(uuid,uuid,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.record_experiment_feedback(uuid,uuid,uuid,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.list_experiments(uuid,integer) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.create_experiment(uuid,uuid,text,text,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.add_experiment_variant(uuid,uuid,text,jsonb) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.record_experiment_feedback(uuid,uuid,uuid,text,text,text) TO app_runtime;

COMMIT;
