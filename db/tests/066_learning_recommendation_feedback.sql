-- Evidence-backed learning-to-recommendation contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $learning_recommendation_gate$
DECLARE
  learning_oid oid;
  recommendation_oid oid;
  feedback_oid oid;
  recommendation_feedback_oid oid;
  learning_definition text;
  recommendation_definition text;
  feedback_definition text;
  recommendation_feedback_definition text;
  helper_owner text;
  helper_definer boolean;
  app_learning_execute boolean;
  public_learning_execute boolean;
  app_recommendation_execute boolean;
  app_feedback_execute boolean;
  app_recommendation_feedback_execute boolean;
  direct_experiment_feedback_select boolean;
  direct_recommendation_feedback_select boolean;
BEGIN
  learning_oid := to_regprocedure('growth.opportunity_learning_context(uuid,uuid)');
  recommendation_oid := to_regprocedure('growth.create_recommendation(uuid,uuid,text)');
  feedback_oid := to_regprocedure('growth.record_experiment_feedback(uuid,uuid,uuid,text,text,text)');
  recommendation_feedback_oid := to_regprocedure('growth.record_recommendation_feedback(uuid,uuid,text,text)');

  IF learning_oid IS NULL OR recommendation_oid IS NULL OR feedback_oid IS NULL
     OR recommendation_feedback_oid IS NULL
  THEN
    RAISE EXCEPTION '066 failed: learning-to-recommendation helper is missing';
  END IF;

  SELECT lower(pg_get_functiondef(learning_oid)) INTO learning_definition;
  SELECT lower(pg_get_functiondef(recommendation_oid)) INTO recommendation_definition;
  SELECT lower(pg_get_functiondef(feedback_oid)) INTO feedback_definition;
  SELECT lower(pg_get_functiondef(recommendation_feedback_oid))
    INTO recommendation_feedback_definition;

  IF position('current_workspace_id' IN learning_definition) = 0
     OR position('tenant_context_valid' IN learning_definition) = 0
     OR position('experiment_feedback' IN learning_definition) = 0
     OR position('recommendation_feedback' IN learning_definition) = 0
     OR position('latest_winner' IN learning_definition) = 0
     OR position('evidence_ref' IN learning_definition) = 0
  THEN
    RAISE EXCEPTION '066 failed: learning context lacks tenant/evidence/feedback lineage';
  END IF;

  IF position('opportunity_learning_context' IN recommendation_definition) = 0
     OR position('recommendation.action.v2' IN recommendation_definition) = 0
     OR position('''learning''' IN recommendation_definition) = 0
     OR position('autonomous_execution' IN recommendation_definition) = 0
  THEN
    RAISE EXCEPTION '066 failed: recommendation creation does not consume measured learning';
  END IF;

  IF position('update growth.recommendations' IN feedback_definition) = 0
     OR position('opportunity_learning_context' IN feedback_definition) = 0
     OR position('''{learning}''' IN feedback_definition) = 0
     OR position('stored evidence reference' IN feedback_definition) = 0
  THEN
    RAISE EXCEPTION '066 failed: experiment feedback does not refresh recommendation learning';
  END IF;

  IF position('opportunity_learning_context' IN recommendation_feedback_definition) = 0
     OR position('''{learning}''' IN recommendation_feedback_definition) = 0
     OR position('update growth.recommendations' IN recommendation_feedback_definition) = 0
  THEN
    RAISE EXCEPTION '066 failed: recommendation feedback does not refresh its learning snapshot';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, helper_definer
    FROM pg_proc p
    JOIN pg_roles r ON r.oid = p.proowner
   WHERE p.oid = learning_oid;

  SELECT has_function_privilege('app_runtime', learning_oid, 'EXECUTE') INTO app_learning_execute;
  SELECT has_function_privilege('public', learning_oid, 'EXECUTE') INTO public_learning_execute;
  SELECT has_function_privilege('app_runtime', recommendation_oid, 'EXECUTE') INTO app_recommendation_execute;
  SELECT has_function_privilege('app_runtime', feedback_oid, 'EXECUTE') INTO app_feedback_execute;
  SELECT has_function_privilege('app_runtime', recommendation_feedback_oid, 'EXECUTE')
    INTO app_recommendation_feedback_execute;
  SELECT has_table_privilege('app_runtime', 'growth.experiment_feedback', 'SELECT')
    INTO direct_experiment_feedback_select;
  SELECT has_table_privilege('app_runtime', 'growth.recommendation_feedback', 'SELECT')
    INTO direct_recommendation_feedback_select;

  IF helper_owner <> 'growth_migrator'
     OR helper_definer IS DISTINCT FROM true
     OR app_learning_execute IS DISTINCT FROM false
     OR public_learning_execute IS DISTINCT FROM false
     OR app_recommendation_execute IS DISTINCT FROM true
     OR app_feedback_execute IS DISTINCT FROM true
     OR app_recommendation_feedback_execute IS DISTINCT FROM true
     OR direct_experiment_feedback_select IS DISTINCT FROM false
     OR direct_recommendation_feedback_select IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '066 failed: learning recommendation privileges are not least-privilege';
  END IF;
END;
$learning_recommendation_gate$;

ROLLBACK;

SELECT 'TEST-066 PASS: evidence-backed learning refreshes recommendations' AS result;
