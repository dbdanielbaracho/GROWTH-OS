-- Worker tenant context and job completion contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $worker_context_gate$
DECLARE
  context_oid oid;
  complete_oid oid;
  context_def text;
  complete_def text;
  helper_owner text;
  is_definer boolean;
  worker_execute boolean;
  public_execute boolean;
  worker_jobs_select boolean;
BEGIN
  context_oid := to_regprocedure('growth.tenant_context_valid(uuid)');
  complete_oid := to_regprocedure(
    'growth.complete_publication_job(uuid,uuid,text,timestamptz,text)'
  );

  IF context_oid IS NULL OR complete_oid IS NULL THEN
    RAISE EXCEPTION '049 failed: worker context helpers are missing';
  END IF;

  SELECT pg_get_functiondef(context_oid) INTO context_def;
  SELECT pg_get_functiondef(complete_oid) INTO complete_def;

  IF position('service_principal_id' IN lower(context_def)) = 0
     OR position('job_id' IN lower(context_def)) = 0
     OR position('leased_until' IN lower(context_def)) = 0
     OR position('retry_wait' IN lower(complete_def)) = 0
     OR position('security definer' IN lower(complete_def)) = 0
  THEN
    RAISE EXCEPTION '049 failed: worker context/completion guards are incomplete';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = complete_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '049 failed: completion helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('growth_worker', complete_oid, 'EXECUTE')
    INTO worker_execute;
  SELECT has_function_privilege('public', complete_oid, 'EXECUTE')
    INTO public_execute;
  SELECT has_table_privilege('growth_worker', 'growth.jobs', 'SELECT')
    INTO worker_jobs_select;

  IF worker_execute IS DISTINCT FROM true
     OR public_execute IS DISTINCT FROM false
     OR worker_jobs_select IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '049 failed: worker completion privileges are too broad or missing';
  END IF;
END;
$worker_context_gate$;

ROLLBACK;

SELECT 'TEST-049 PASS: worker tenant context and job completion contract' AS result;
