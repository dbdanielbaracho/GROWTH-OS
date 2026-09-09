-- Automation approval, quota and kill-switch contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $automation_gate$
DECLARE
  oid_policy oid;
  oid_set oid;
  oid_list oid;
  oid_create oid;
  oid_decide oid;
  definition text;
  owner_name text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  direct_policy_select boolean;
  direct_request_select boolean;
  rls_policy boolean;
  rls_request boolean;
BEGIN
  oid_policy := to_regprocedure('growth.get_automation_policy(uuid)');
  oid_set := to_regprocedure('growth.set_automation_policy(uuid,text,integer,boolean)');
  oid_list := to_regprocedure('growth.list_automation_action_requests(uuid,integer)');
  oid_create := to_regprocedure('growth.create_automation_action_request(uuid,text,text,text,text)');
  oid_decide := to_regprocedure('growth.decide_automation_action_request(uuid,uuid,text,text)');

  IF oid_policy IS NULL OR oid_set IS NULL OR oid_list IS NULL
     OR oid_create IS NULL OR oid_decide IS NULL
  THEN
    RAISE EXCEPTION '054 failed: automation helper is missing';
  END IF;

  SELECT string_agg(pg_get_functiondef(p.oid), E'\n')
    INTO definition
    FROM pg_proc p
   WHERE p.oid IN (oid_policy, oid_set, oid_list, oid_create, oid_decide);

  IF position('kill_switch' IN lower(definition)) = 0
     OR position('daily_request_limit' IN lower(definition)) = 0
     OR position('approval requires owner or admin' IN lower(definition)) = 0
     OR position('requires stored evidence reference' IN lower(definition)) = 0
     OR position('pending' IN lower(definition)) = 0
  THEN
    RAISE EXCEPTION '054 failed: automation boundaries are incomplete';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO owner_name, is_definer
    FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
   WHERE p.oid = oid_create;
  IF owner_name <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '054 failed: automation owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', oid_create, 'EXECUTE')
    INTO app_execute;
  SELECT has_function_privilege('public', oid_create, 'EXECUTE')
    INTO public_execute;
  SELECT has_table_privilege('app_runtime', 'growth.automation_policies', 'SELECT')
    INTO direct_policy_select;
  SELECT has_table_privilege('app_runtime', 'growth.automation_action_requests', 'SELECT')
    INTO direct_request_select;
  SELECT c.relrowsecurity
    INTO rls_policy
    FROM pg_class c
   WHERE c.oid = 'growth.automation_policies'::regclass;
  SELECT c.relforcerowsecurity
    INTO rls_request
    FROM pg_class c
   WHERE c.oid = 'growth.automation_action_requests'::regclass;

  IF app_execute IS DISTINCT FROM true OR public_execute IS DISTINCT FROM false
     OR direct_policy_select IS DISTINCT FROM false
     OR direct_request_select IS DISTINCT FROM false
     OR rls_policy IS DISTINCT FROM true
     OR rls_request IS DISTINCT FROM true
  THEN
    RAISE EXCEPTION '054 failed: automation privilege/RLS boundary';
  END IF;
END;
$automation_gate$;

ROLLBACK;

SELECT 'TEST-054 PASS: approval-gated automation control plane' AS result;
