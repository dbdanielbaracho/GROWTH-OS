-- Scheduled publication calendar -> queue proof.
-- No provider adapter or network call occurs; all smoke data rolls back.
\set ON_ERROR_STOP on

BEGIN;

DO $catalog_gate$
DECLARE
  schedule_oid oid := to_regprocedure('growth.schedule_publication_intent(uuid,uuid,timestamptz)');
  dispatch_oid oid := to_regprocedure('growth.enqueue_due_scheduled_publications(uuid,timestamptz,integer)');
  owner_name text;
BEGIN
  IF schedule_oid IS NULL OR dispatch_oid IS NULL THEN
    RAISE EXCEPTION '070 failed: scheduling/dispatch helper missing';
  END IF;

  SELECT r.rolname INTO owner_name
  FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = schedule_oid;
  IF owner_name <> 'growth_migrator'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = schedule_oid)
     OR NOT has_function_privilege('app_runtime', schedule_oid, 'EXECUTE')
     OR has_function_privilege('public', schedule_oid, 'EXECUTE')
  THEN
    RAISE EXCEPTION '070 failed: schedule helper privilege boundary';
  END IF;

  SELECT r.rolname INTO owner_name
  FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = dispatch_oid;
  IF owner_name <> 'growth_migrator'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = dispatch_oid)
     OR NOT has_function_privilege('growth_worker', dispatch_oid, 'EXECUTE')
     OR has_function_privilege('public', dispatch_oid, 'EXECUTE')
  THEN
    RAISE EXCEPTION '070 failed: dispatch helper privilege boundary';
  END IF;
END;
$catalog_gate$;

DO $seed$
DECLARE
  workspace_id uuid := 'f0700000-0000-4000-8000-000000000001';
  user_id uuid := 'f0700000-0000-4000-8000-000000000002';
BEGIN
  INSERT INTO growth.workspaces(id,name,default_market,default_language,default_timezone,status)
  VALUES(workspace_id,'gate-070-scheduling','US','en','UTC','active');

  INSERT INTO growth.users(id,email,status)
  VALUES(user_id,'gate-070@example.invalid','active');

  PERFORM set_config('app.workspace_id', workspace_id::text, true);
  PERFORM set_config('app.user_id', user_id::text, true);

  INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
  VALUES(workspace_id,user_id,'owner',true,'active');

  INSERT INTO growth.managed_accounts(id,workspace_id,owner_type,authority_status,contribution_eligibility)
  VALUES('f0700000-0000-4000-8000-000000000003',workspace_id,'direct','contractually_granted','private_only');

  INSERT INTO growth.platform_connections(id,workspace_id,managed_account_id,platform,state)
  VALUES('f0700000-0000-4000-8000-000000000004',workspace_id,'f0700000-0000-4000-8000-000000000003','gate_test','connected');

  INSERT INTO growth.social_accounts(
    id,workspace_id,managed_account_id,platform_connection_id,platform,
    provider_account_id,handle,account_type,market,timezone
  ) VALUES(
    'f0700000-0000-4000-8000-000000000005',workspace_id,
    'f0700000-0000-4000-8000-000000000003','f0700000-0000-4000-8000-000000000004',
    'gate_test','gate-070-provider','gate070','test','US','UTC'
  );

  INSERT INTO growth.content_items(
    id,workspace_id,objective,market,language,platform_target,source_type,status,created_by
  ) VALUES(
    'f0700000-0000-4000-8000-000000000006',workspace_id,
    'scheduled dispatch smoke','US','en','gate_test','manual','approved',user_id
  );

  INSERT INTO growth.content_versions(id,workspace_id,content_item_id,version_no,body,checksum)
  VALUES(
    'f0700000-0000-4000-8000-000000000007',workspace_id,
    'f0700000-0000-4000-8000-000000000006',1,'scheduled dispatch smoke','gate-070-version'
  );

  INSERT INTO growth.publication_intents(
    id,workspace_id,social_account_id,content_version_id,request_nonce,idempotency_key,status
  ) VALUES(
    'f0700000-0000-4000-8000-000000000008',workspace_id,
    'f0700000-0000-4000-8000-000000000005','f0700000-0000-4000-8000-000000000007',
    'f0700000-0000-4000-8000-000000000009','gate-070-scheduled-intent','ready'
  );

  INSERT INTO growth.worker_service_principals(id,name,status,allowed_job_types)
  VALUES(
    'f0700000-0000-4000-8000-000000000010','gate-070-worker','active',ARRAY['publication_intent']::text[]
  );
END;
$seed$;

SET LOCAL ROLE app_runtime;
SELECT set_config('app.workspace_id','f0700000-0000-4000-8000-000000000001',true);
SELECT set_config('app.user_id','f0700000-0000-4000-8000-000000000002',true);

DO $past_rejected$
BEGIN
  BEGIN
    PERFORM growth.schedule_publication_intent(
      'f0700000-0000-4000-8000-000000000001',
      'f0700000-0000-4000-8000-000000000008',
      now() - interval '1 minute'
    );
    RAISE EXCEPTION '070 failed: past schedule was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF position('future timestamp' IN SQLERRM) = 0 THEN RAISE; END IF;
  END;
END;
$past_rejected$;

SELECT growth.schedule_publication_intent(
  'f0700000-0000-4000-8000-000000000001',
  'f0700000-0000-4000-8000-000000000008',
  now() + interval '2 seconds'
);

RESET ROLE;

SET LOCAL ROLE growth_worker;
DO $dispatch_smoke$
DECLARE
  early_count integer;
  due_count integer;
BEGIN
  SELECT growth.enqueue_due_scheduled_publications(
    'f0700000-0000-4000-8000-000000000010', now(), 10
  ) INTO early_count;
  IF early_count <> 0 THEN
    RAISE EXCEPTION '070 failed: scheduled intent enqueued before due time';
  END IF;

  SELECT growth.enqueue_due_scheduled_publications(
    'f0700000-0000-4000-8000-000000000010', now() + interval '3 seconds', 10
  ) INTO due_count;
  IF due_count <> 1 THEN
    RAISE EXCEPTION '070 failed: due scheduled intent was not enqueued exactly once';
  END IF;
END;
$dispatch_smoke$;
RESET ROLE;

DO $verify$
DECLARE
  intent_status text;
  intent_scheduled_for timestamptz;
  job_state text;
  job_principal uuid;
BEGIN
  SELECT status, scheduled_for INTO intent_status, intent_scheduled_for
  FROM growth.publication_intents
  WHERE id = 'f0700000-0000-4000-8000-000000000008';

  SELECT state, service_principal_id INTO job_state, job_principal
  FROM growth.jobs
  WHERE workspace_id = 'f0700000-0000-4000-8000-000000000001'
    AND job_type = 'publication_intent'
    AND operation_key = 'f0700000-0000-4000-8000-000000000008';

  IF intent_status IS DISTINCT FROM 'queued'
     OR intent_scheduled_for IS NULL
     OR job_state IS DISTINCT FROM 'queued'
     OR job_principal IS DISTINCT FROM 'f0700000-0000-4000-8000-000000000010'::uuid
  THEN
    RAISE EXCEPTION '070 failed: calendar -> queue state is incomplete';
  END IF;
END;
$verify$;

ROLLBACK;

SELECT 'TEST-070 PASS: future scheduling enforced; not-due skipped; due intent queued once; rollback complete' AS result;
