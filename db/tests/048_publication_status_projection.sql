-- Publication status projection contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $status_gate$
DECLARE
  status_oid oid;
  queue_status_oid oid;
  status_def text;
  queue_status_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  runtime_direct boolean;
BEGIN
  status_oid := to_regprocedure(
    'growth.list_publication_intents(uuid,integer)'
  );
  queue_status_oid := to_regprocedure(
    'growth.list_publication_intents_v2(uuid,integer)'
  );

  IF status_oid IS NULL OR queue_status_oid IS NULL THEN
    RAISE EXCEPTION '048 failed: publication status helper is missing';
  END IF;

  SELECT pg_get_functiondef(status_oid) INTO status_def;
  IF position('security definer' IN lower(status_def)) = 0
     OR position('current_workspace_id' IN lower(status_def)) = 0
     OR position('tenant_context_valid' IN lower(status_def)) = 0
     OR position('credential' IN lower(status_def)) > 0
     OR position('payload' IN lower(status_def)) > 0
  THEN
    RAISE EXCEPTION '048 failed: status helper exposes an unsafe projection';
  END IF;

  SELECT pg_get_functiondef(queue_status_oid) INTO queue_status_def;
  IF position('security definer' IN lower(queue_status_def)) = 0
     OR position('current_workspace_id' IN lower(queue_status_def)) = 0
     OR position('tenant_context_valid' IN lower(queue_status_def)) = 0
     OR position('queue_state' IN lower(queue_status_def)) = 0
     OR position('j.state' IN lower(queue_status_def)) = 0
     OR position('j.attempts' IN lower(queue_status_def)) = 0
     OR position('payload' IN lower(queue_status_def)) > 0
     OR position('service_principal_id' IN lower(queue_status_def)) > 0
     OR position('leased_until' IN lower(queue_status_def)) > 0
  THEN
    RAISE EXCEPTION '048 failed: queue status helper projection is incomplete or unsafe';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = queue_status_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '048 failed: queue status helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', queue_status_oid, 'EXECUTE')
    INTO app_execute;
  SELECT has_function_privilege('public', queue_status_oid, 'EXECUTE')
    INTO public_execute;
  SELECT has_table_privilege('app_runtime', 'growth.jobs', 'SELECT')
    INTO runtime_direct;

  IF app_execute IS DISTINCT FROM true
     OR public_execute IS DISTINCT FROM false
     OR runtime_direct IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '048 failed: status helper privileges are not least-privilege';
  END IF;
END;
$status_gate$;

ROLLBACK;

SELECT 'TEST-048 PASS: publication status and dead-letter projection contract' AS result;
