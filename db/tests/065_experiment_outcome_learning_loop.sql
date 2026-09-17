-- Persisted experiment learning loop contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $experiment_learning_gate$
DECLARE
  list_oid oid;
  variant_oid oid;
  feedback_oid oid;
  list_definition text;
  variant_definition text;
  feedback_definition text;
  helper_owner text;
  helper_definer boolean;
  app_execute boolean;
  public_execute boolean;
  direct_variant_select boolean;
  direct_feedback_select boolean;
BEGIN
  list_oid := to_regprocedure('growth.list_experiment_variants(uuid,uuid)');
  variant_oid := to_regprocedure('growth.add_experiment_variant(uuid,uuid,text,jsonb)');
  feedback_oid := to_regprocedure('growth.record_experiment_feedback(uuid,uuid,uuid,text,text,text)');

  IF list_oid IS NULL OR variant_oid IS NULL OR feedback_oid IS NULL THEN
    RAISE EXCEPTION '065 failed: experiment learning helper is missing';
  END IF;

  SELECT lower(pg_get_functiondef(list_oid)) INTO list_definition;
  SELECT lower(pg_get_functiondef(variant_oid)) INTO variant_definition;
  SELECT lower(pg_get_functiondef(feedback_oid)) INTO feedback_definition;

  IF position('current_workspace_id' IN list_definition) = 0
     OR position('tenant_context_valid' IN list_definition) = 0
     OR position('experiment_feedback' IN list_definition) = 0
     OR position('latest' IN list_definition) = 0
  THEN
    RAISE EXCEPTION '065 failed: variant listing lacks tenant/latest-feedback guards';
  END IF;

  IF position('status in (''draft'', ''running'')' IN variant_definition) = 0
     OR position('update growth.experiments' IN variant_definition) = 0
     OR position('status = ''running''' IN variant_definition) = 0
  THEN
    RAISE EXCEPTION '065 failed: variant helper does not advance/reopen running work';
  END IF;

  IF position('update growth.experiments' IN feedback_definition) = 0
     OR position('p_outcome = ''winner''' IN feedback_definition) = 0
     OR position('''completed''' IN feedback_definition) = 0
     OR position('stored evidence reference' IN feedback_definition) = 0
  THEN
    RAISE EXCEPTION '065 failed: feedback helper lacks evidence-backed learning transition';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, helper_definer
    FROM pg_proc p
    JOIN pg_roles r ON r.oid = p.proowner
   WHERE p.oid = list_oid;

  SELECT has_function_privilege('app_runtime', list_oid, 'EXECUTE') INTO app_execute;
  SELECT has_function_privilege('public', list_oid, 'EXECUTE') INTO public_execute;
  SELECT has_table_privilege('app_runtime', 'growth.experiment_variant_plans', 'SELECT') INTO direct_variant_select;
  SELECT has_table_privilege('app_runtime', 'growth.experiment_feedback', 'SELECT') INTO direct_feedback_select;

  IF helper_owner <> 'growth_migrator'
     OR helper_definer IS DISTINCT FROM true
     OR app_execute IS DISTINCT FROM true
     OR public_execute IS DISTINCT FROM false
     OR direct_variant_select IS DISTINCT FROM false
     OR direct_feedback_select IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '065 failed: experiment learning privileges are not least-privilege';
  END IF;
END;
$experiment_learning_gate$;

ROLLBACK;

SELECT 'TEST-065 PASS: persisted experiment outcome learning loop' AS result;
