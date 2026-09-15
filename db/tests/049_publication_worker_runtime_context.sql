-- Worker tenant context, job completion and operational queue lifecycle gate.
-- The lifecycle proof is fully transactional and rolls back all smoke data.
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

DO $seed_lifecycle_smoke$
DECLARE
  service_id uuid := 'f0000000-0000-4000-8000-000000000049';
  job_id uuid := 'f0000000-0000-4000-8000-000000000050';
  workspace_id uuid;
BEGIN
  SELECT id INTO workspace_id
  FROM growth.workspaces
  ORDER BY id
  LIMIT 1;

  IF workspace_id IS NULL THEN
    RAISE EXCEPTION '049 failed: no workspace exists for transactional queue lifecycle proof';
  END IF;

  INSERT INTO growth.worker_service_principals(
    id, name, status, allowed_job_types
  )
  VALUES(
    service_id,
    'gate-publication-lifecycle',
    'active',
    ARRAY['publication_intent']
  );

  INSERT INTO growth.jobs(
    id, workspace_id, job_type, operation_key, payload, state,
    available_at, service_principal_id
  )
  VALUES(
    job_id,
    workspace_id,
    'publication_intent',
    'gate-049-lifecycle',
    jsonb_build_object(
      'publication_intent_id',
      'f0000000-0000-4000-8000-000000000051'
    ),
    'queued',
    now(),
    service_id
  );
END;
$seed_lifecycle_smoke$;

SET LOCAL ROLE growth_worker;

DO $queue_lifecycle_smoke$
DECLARE
  service_id uuid := 'f0000000-0000-4000-8000-000000000049';
  job_id uuid := 'f0000000-0000-4000-8000-000000000050';
  claimed growth.jobs;
  completed growth.jobs;
BEGIN
  SELECT * INTO claimed
  FROM growth.claim_due_publication_job(service_id, now(), 60)
  LIMIT 1;

  IF NOT FOUND
     OR claimed.id IS DISTINCT FROM job_id
     OR claimed.state IS DISTINCT FROM 'leased'
     OR claimed.attempts IS DISTINCT FROM 1
  THEN
    RAISE EXCEPTION '049 failed: queued job did not enter first leased attempt';
  END IF;

  SELECT * INTO completed
  FROM growth.complete_publication_job(
    service_id,
    job_id,
    'retry_wait',
    now() + interval '1 minute',
    'smoke.retry'
  );

  IF completed.state IS DISTINCT FROM 'retry_wait'
     OR completed.attempts IS DISTINCT FROM 1
     OR completed.leased_until IS NOT NULL
     OR completed.last_error_class IS DISTINCT FROM 'smoke.retry'
  THEN
    RAISE EXCEPTION '049 failed: first attempt did not enter retry_wait safely';
  END IF;

  SELECT * INTO claimed
  FROM growth.claim_due_publication_job(
    service_id,
    now() + interval '2 minutes',
    60
  )
  LIMIT 1;

  IF NOT FOUND
     OR claimed.id IS DISTINCT FROM job_id
     OR claimed.state IS DISTINCT FROM 'leased'
     OR claimed.attempts IS DISTINCT FROM 2
  THEN
    RAISE EXCEPTION '049 failed: retry_wait job did not enter second leased attempt';
  END IF;

  SELECT * INTO completed
  FROM growth.complete_publication_job(
    service_id,
    job_id,
    'dead',
    NULL,
    'smoke.dead'
  );

  IF completed.state IS DISTINCT FROM 'dead'
     OR completed.attempts IS DISTINCT FROM 2
     OR completed.leased_until IS NOT NULL
     OR completed.last_error_class IS DISTINCT FROM 'smoke.dead'
  THEN
    RAISE EXCEPTION '049 failed: second attempt did not enter terminal dead state';
  END IF;

  SELECT * INTO claimed
  FROM growth.claim_due_publication_job(
    service_id,
    now() + interval '10 minutes',
    60
  )
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION '049 failed: terminal dead job was claimable again';
  END IF;
END;
$queue_lifecycle_smoke$;

ROLLBACK;

SELECT 'TEST-049 PASS: queued -> leased(1) -> retry_wait -> leased(2) -> dead; rollback complete' AS result;
