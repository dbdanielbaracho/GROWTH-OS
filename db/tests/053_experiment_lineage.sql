-- Experiment and multiplication contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $experiment_gate$
DECLARE
  oid_list oid;
  oid_create oid;
  oid_variant oid;
  oid_feedback oid;
  definition text;
  owner_name text;
  is_definer boolean;
  direct_variant_select boolean;
  direct_feedback_select boolean;
  app_execute boolean;
  public_execute boolean;
BEGIN
  oid_list := to_regprocedure('growth.list_experiments(uuid,integer)');
  oid_create := to_regprocedure('growth.create_experiment(uuid,uuid,text,text,text)');
  oid_variant := to_regprocedure('growth.add_experiment_variant(uuid,uuid,text,jsonb)');
  oid_feedback := to_regprocedure('growth.record_experiment_feedback(uuid,uuid,uuid,text,text,text)');
  IF oid_list IS NULL OR oid_create IS NULL OR oid_variant IS NULL OR oid_feedback IS NULL THEN
    RAISE EXCEPTION '053 failed: experiment helper is missing';
  END IF;

  SELECT string_agg(pg_get_functiondef(p.oid), E'\n')
    INTO definition
    FROM pg_proc p
   WHERE p.oid IN (oid_list, oid_create, oid_variant, oid_feedback);

  IF position('current_workspace_id' IN lower(definition)) = 0
     OR position('tenant_context_valid' IN lower(definition)) = 0
     OR position('opportunity_evidence' IN lower(definition)) = 0
     OR position('source_opportunity_id' IN lower(definition)) = 0
     OR position('stored evidence reference' IN lower(definition)) = 0
  THEN
    RAISE EXCEPTION '053 failed: experiment helpers lack tenant/lineage/evidence guards';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO owner_name, is_definer
    FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
   WHERE p.oid = oid_list;
  IF owner_name <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '053 failed: experiment helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', oid_list, 'EXECUTE')
    INTO app_execute;
  SELECT has_function_privilege('public', oid_list, 'EXECUTE')
    INTO public_execute;
  SELECT has_table_privilege('app_runtime', 'growth.experiment_variant_plans', 'SELECT')
    INTO direct_variant_select;
  SELECT has_table_privilege('app_runtime', 'growth.experiment_feedback', 'SELECT')
    INTO direct_feedback_select;

  IF app_execute IS DISTINCT FROM true OR public_execute IS DISTINCT FROM false
     OR direct_variant_select IS DISTINCT FROM false
     OR direct_feedback_select IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '053 failed: experiment privileges are not least-privilege';
  END IF;
END;
$experiment_gate$;

ROLLBACK;

SELECT 'TEST-053 PASS: experiment lineage and feedback boundary' AS result;
