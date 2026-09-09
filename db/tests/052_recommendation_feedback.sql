-- Recommendation storage and feedback contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $recommendation_gate$
DECLARE
  list_oid oid;
  create_oid oid;
  feedback_oid oid;
  definition text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  direct_recommendation_select boolean;
  direct_feedback_select boolean;
  recommendations_rls boolean;
  recommendations_force_rls boolean;
  feedback_rls boolean;
  feedback_force_rls boolean;
BEGIN
  list_oid := to_regprocedure('growth.list_recommendations(uuid,uuid,integer)');
  create_oid := to_regprocedure('growth.create_recommendation(uuid,uuid,text)');
  feedback_oid := to_regprocedure('growth.record_recommendation_feedback(uuid,uuid,text,text)');

  IF list_oid IS NULL OR create_oid IS NULL OR feedback_oid IS NULL THEN
    RAISE EXCEPTION '052 failed: recommendation helper is missing';
  END IF;

  SELECT string_agg(pg_get_functiondef(p.oid), E'\n')
    INTO definition
    FROM pg_proc p
   WHERE p.oid IN (list_oid, create_oid, feedback_oid);

  IF position('current_workspace_id' IN lower(definition)) = 0
     OR position('tenant_context_valid' IN lower(definition)) = 0
     OR position('opportunity_evidence' IN lower(definition)) = 0
     OR position('autonomous_execution' IN lower(definition)) = 0
  THEN
    RAISE EXCEPTION '052 failed: recommendation helpers lack tenant/evidence/no-autonomy guards';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
    FROM pg_proc p
    JOIN pg_roles r ON r.oid = p.proowner
   WHERE p.oid = list_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '052 failed: list helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', list_oid, 'EXECUTE')
    INTO app_execute;
  SELECT has_function_privilege('public', list_oid, 'EXECUTE')
    INTO public_execute;
  SELECT has_table_privilege('app_runtime', 'growth.recommendations', 'SELECT')
    INTO direct_recommendation_select;
  SELECT has_table_privilege('app_runtime', 'growth.recommendation_feedback', 'SELECT')
    INTO direct_feedback_select;

  IF app_execute IS DISTINCT FROM true
     OR public_execute IS DISTINCT FROM false
     OR direct_recommendation_select IS DISTINCT FROM false
     OR direct_feedback_select IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '052 failed: recommendation privileges are not least-privilege';
  END IF;

  SELECT relrowsecurity, relforcerowsecurity
    INTO recommendations_rls, recommendations_force_rls
    FROM pg_class
   WHERE oid = 'growth.recommendations'::regclass;

  SELECT relrowsecurity, relforcerowsecurity
    INTO feedback_rls, feedback_force_rls
    FROM pg_class
   WHERE oid = 'growth.recommendation_feedback'::regclass;

  IF recommendations_rls IS DISTINCT FROM true
     OR recommendations_force_rls IS DISTINCT FROM true
     OR feedback_rls IS DISTINCT FROM true
     OR feedback_force_rls IS DISTINCT FROM true
  THEN
    RAISE EXCEPTION '052 failed: recommendation tables must use RLS and FORCE RLS';
  END IF;
END;
$recommendation_gate$;

ROLLBACK;

SELECT 'TEST-052 PASS: recommendation storage and feedback boundary' AS result;
