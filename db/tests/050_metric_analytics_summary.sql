-- Analytics summary projection contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $analytics_gate$
DECLARE
  analytics_oid oid;
  analytics_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  runtime_direct boolean;
BEGIN
  analytics_oid := to_regprocedure(
    'growth.list_metric_analytics_summary(uuid,timestamp with time zone,timestamp with time zone)'
  );

  IF analytics_oid IS NULL THEN
    RAISE EXCEPTION '050 failed: analytics summary helper is missing';
  END IF;

  SELECT pg_get_functiondef(analytics_oid) INTO analytics_def;
  IF position('security definer' IN lower(analytics_def)) = 0
     OR position('current_workspace_id' IN lower(analytics_def)) = 0
     OR position('metric_observations' IN lower(analytics_def)) = 0
     OR position('completeness_status' IN lower(analytics_def)) = 0
     OR position('freshness_status' IN lower(analytics_def)) = 0
     OR position('366 days' IN lower(analytics_def)) = 0
  THEN
    RAISE EXCEPTION '050 failed: analytics summary lacks tenant/provenance/window guards';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = analytics_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '050 failed: analytics helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', analytics_oid, 'EXECUTE')
    INTO app_execute;
  SELECT has_function_privilege('public', analytics_oid, 'EXECUTE')
    INTO public_execute;
  SELECT has_table_privilege('app_runtime', 'growth.metric_observations', 'SELECT')
    INTO runtime_direct;

  IF app_execute IS DISTINCT FROM true
     OR public_execute IS DISTINCT FROM false
     OR runtime_direct IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '050 failed: analytics helper privileges are not least-privilege';
  END IF;
END;
$analytics_gate$;

ROLLBACK;

SELECT 'TEST-050 PASS: metric analytics summary projection' AS result;
