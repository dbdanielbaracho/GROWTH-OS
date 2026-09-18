-- Growth OS — approval-gated automation execution contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $automation_execution_gate$
DECLARE
  oid_list oid;
  oid_create oid;
  oid_decide oid;
  oid_claim oid;
  oid_finalize oid;
  definitions text;
  owner_name text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  direct_update boolean;
  payload_column boolean;
  execution_column boolean;
BEGIN
  oid_list := to_regprocedure('growth.list_automation_action_requests_v2(uuid,integer)');
  oid_create := to_regprocedure('growth.create_automation_action_request_v2(uuid,text,text,text,text,jsonb)');
  oid_decide := to_regprocedure('growth.decide_automation_action_request_v2(uuid,uuid,text,text)');
  oid_claim := to_regprocedure('growth.claim_automation_action_execution(uuid,uuid)');
  oid_finalize := to_regprocedure('growth.finalize_automation_action_execution(uuid,uuid,text,text,text)');

  IF oid_list IS NULL OR oid_create IS NULL OR oid_decide IS NULL
     OR oid_claim IS NULL OR oid_finalize IS NULL
  THEN
    RAISE EXCEPTION '069 failed: automation execution helper is missing';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'growth'
       AND table_name = 'automation_action_requests'
       AND column_name = 'action_payload'
       AND data_type = 'jsonb'
  ) INTO payload_column;
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'growth'
       AND table_name = 'automation_action_requests'
       AND column_name = 'execution_status'
  ) INTO execution_column;
  IF NOT payload_column OR NOT execution_column THEN
    RAISE EXCEPTION '069 failed: execution state columns are missing';
  END IF;

  SELECT string_agg(pg_get_functiondef(p.oid), E'\n')
    INTO definitions
    FROM pg_proc p
   WHERE p.oid IN (oid_create, oid_decide, oid_claim, oid_finalize);

  IF position('action payload must be an object' IN lower(definitions)) = 0
     OR position('execution requires owner or admin' IN lower(definitions)) = 0
     OR position('blocked by policy or kill switch' IN lower(definitions)) = 0
     OR position('status = ''approved''' IN lower(definitions)) = 0
     OR position('execution_status = ''ready''' IN lower(definitions)) = 0
     OR position('execution_status = ''executing''' IN lower(definitions)) = 0
  THEN
    RAISE EXCEPTION '069 failed: approval/execution safety boundaries are incomplete';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO owner_name, is_definer
    FROM pg_proc p
    JOIN pg_roles r ON r.oid = p.proowner
   WHERE p.oid = oid_claim;
  IF owner_name <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '069 failed: execution claim owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', oid_claim, 'EXECUTE') INTO app_execute;
  SELECT has_function_privilege('public', oid_claim, 'EXECUTE') INTO public_execute;
  SELECT has_table_privilege('app_runtime', 'growth.automation_action_requests', 'UPDATE') INTO direct_update;

  IF app_execute IS DISTINCT FROM true
     OR public_execute IS DISTINCT FROM false
     OR direct_update IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '069 failed: execution privilege boundary';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint c
      JOIN pg_class t ON t.oid = c.conrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace
     WHERE n.nspname = 'growth'
       AND t.relname = 'automation_action_requests'
       AND c.conname = 'automation_action_payload_object'
  ) THEN
    RAISE EXCEPTION '069 failed: action payload object constraint missing';
  END IF;
END;
$automation_execution_gate$;

ROLLBACK;

SELECT 'TEST-069 PASS: approved automation actions have bounded auditable execution state' AS result;
