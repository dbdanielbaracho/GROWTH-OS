-- Publication worker service-principal and queue-claim contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $worker_gate$
DECLARE
  enqueue_oid oid;
  claim_oid oid;
  claim_def text;
  helper_owner text;
  is_definer boolean;
  worker_execute boolean;
  public_execute boolean;
  worker_jobs_select boolean;
  app_jobs_select boolean;
  service_id uuid := 'f0000000-0000-4000-8000-000000000047';
  workspace_id uuid;
  job_id uuid := 'f0000000-0000-4000-8000-000000000048';
  claimed growth.jobs;
BEGIN
  enqueue_oid := to_regprocedure(
    'growth.enqueue_publication_job(uuid,uuid,uuid,timestamptz)'
  );
  claim_oid := to_regprocedure(
    'growth.claim_due_publication_job(uuid,timestamptz,integer)'
  );

  IF enqueue_oid IS NULL OR claim_oid IS NULL THEN
    RAISE EXCEPTION '047 failed: queue helpers are missing';
  END IF;

  SELECT pg_get_functiondef(claim_oid) INTO claim_def;
  IF position('security definer' IN lower(claim_def)) = 0
     OR position('skip locked' IN lower(claim_def)) = 0
     OR position('service_principal_id' IN lower(claim_def)) = 0
     OR position('leased' IN lower(claim_def)) = 0
  THEN
    RAISE EXCEPTION '047 failed: claim helper lacks queue/lease boundary';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = claim_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '047 failed: claim helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('growth_worker', claim_oid, 'EXECUTE')
    INTO worker_execute;
  SELECT has_function_privilege('public', claim_oid, 'EXECUTE')
    INTO public_execute;

  IF worker_execute IS DISTINCT FROM true
     OR public_execute IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '047 failed: worker/public claim privileges';
  END IF;

  SELECT has_table_privilege('growth_worker', 'growth.jobs', 'SELECT')
    INTO worker_jobs_select;
  SELECT has_table_privilege('app_runtime', 'growth.jobs', 'SELECT')
    INTO app_jobs_select;

  IF worker_jobs_select IS DISTINCT FROM false
     OR app_jobs_select IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '047 failed: direct jobs table access is too broad';
  END IF;

  SELECT id INTO workspace_id
  FROM growth.workspaces
  ORDER BY id
  LIMIT 1;

  IF workspace_id IS NULL THEN
    RAISE EXCEPTION '047 failed: no isolated workspace fixture exists';
  END IF;

  INSERT INTO growth.worker_service_principals(
    id, name, status, allowed_job_types
  )
  VALUES(service_id, 'gate-publication-worker', 'active', ARRAY['publication_intent']);

  INSERT INTO growth.jobs(
    id, workspace_id, job_type, operation_key, payload, state,
    available_at, service_principal_id
  )
  VALUES(
    job_id, workspace_id, 'publication_intent', 'gate-047',
    jsonb_build_object('publication_intent_id', 'f0000000-0000-4000-8000-000000000049'),
    'queued', now(), service_id
  );

  SELECT * INTO claimed
  FROM growth.claim_due_publication_job(service_id, now(), 60)
  LIMIT 1;

  IF claimed.id IS DISTINCT FROM job_id
     OR claimed.state IS DISTINCT FROM 'leased'
     OR claimed.service_principal_id IS DISTINCT FROM service_id
     OR claimed.attempts IS DISTINCT FROM 1
  THEN
    RAISE EXCEPTION '047 failed: due job was not atomically leased';
  END IF;
END;
$worker_gate$;

ROLLBACK;

SELECT 'TEST-047 PASS: publication worker service principal and queue claim' AS result;
