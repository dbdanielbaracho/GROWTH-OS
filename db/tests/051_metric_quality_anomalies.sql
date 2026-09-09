-- Metric quality anomaly projection contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $quality_gate$
DECLARE
  quality_oid oid;
  quality_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  runtime_direct boolean;
BEGIN
  quality_oid := to_regprocedure(
    'growth.list_metric_quality_anomalies(uuid,timestamp with time zone,timestamp with time zone)'
  );

  IF quality_oid IS NULL THEN
    RAISE EXCEPTION '051 failed: metric quality helper is missing';
  END IF;

  SELECT pg_get_functiondef(quality_oid) INTO quality_def;
  IF position('security definer' IN lower(quality_def)) = 0
     OR position('current_workspace_id' IN lower(quality_def)) = 0
     OR position('tenant_context_valid' IN lower(quality_def)) = 0
     OR position('metric_observations' IN lower(quality_def)) = 0
     OR position('completeness_status' IN lower(quality_def)) = 0
     OR position('freshness_status' IN lower(quality_def)) = 0
     OR position('366 days' IN lower(quality_def)) = 0
  THEN
    RAISE EXCEPTION '051 failed: quality helper lacks tenant/provenance/window guards';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = quality_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '051 failed: quality helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', quality_oid, 'EXECUTE')
    INTO app_execute;
  SELECT has_function_privilege('public', quality_oid, 'EXECUTE')
    INTO public_execute;
  SELECT has_table_privilege('app_runtime', 'growth.metric_observations', 'SELECT')
    INTO runtime_direct;

  IF app_execute IS DISTINCT FROM true
     OR public_execute IS DISTINCT FROM false
     OR runtime_direct IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '051 failed: quality helper privileges are not least-privilege';
  END IF;
END;
$quality_gate$;

ROLLBACK;

SELECT 'TEST-051 PASS: metric quality anomaly projection' AS result;
