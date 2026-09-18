-- Growth OS — qualify experiment status inside the variant helper.
-- Forward-only migration 067.
--
-- The TABLE return signature exposes a PL/pgSQL output variable named
-- `status`. Migration 063 used an unqualified `status` predicate in an UPDATE,
-- so the real app_runtime path failed with an ambiguous-column error as soon
-- as it added the first variant. Keep the function boundary and qualify the
-- target table explicitly.

\set ON_ERROR_STOP on

BEGIN;

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

  UPDATE growth.experiments AS e
     SET status = 'running',
         started_at = coalesce(e.started_at, now())
   WHERE e.workspace_id = p_workspace_id
     AND e.id = p_experiment_id
     AND e.status = 'draft';
END;
$$;

ALTER FUNCTION growth.add_experiment_variant(uuid,uuid,text,jsonb) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.add_experiment_variant(uuid,uuid,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.add_experiment_variant(uuid,uuid,text,jsonb) TO app_runtime;

DO $$
DECLARE
  function_definition text;
BEGIN
  SELECT lower(pg_get_functiondef('growth.add_experiment_variant(uuid,uuid,text,jsonb)'::regprocedure))
    INTO function_definition;

  IF position('and e.status = ''draft''' in function_definition) = 0
     OR position('and status = ''draft''' in function_definition) > 0
  THEN
    RAISE EXCEPTION '067 did not install the qualified experiment status predicate';
  END IF;
END $$;

COMMIT;
