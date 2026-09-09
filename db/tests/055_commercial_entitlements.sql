-- Commercial entitlements and enterprise governance contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $commercial_gate$
DECLARE
  oid_entitlements oid;
  oid_usage oid;
  oid_subscription oid;
  oid_enterprise oid;
  definition text;
  owner_name text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  direct_sub_select boolean;
  direct_usage_select boolean;
  rls_sub boolean;
  rls_enterprise boolean;
  usage_after bigint;
  limit_blocked boolean;
BEGIN
  oid_entitlements := to_regprocedure('growth.get_workspace_entitlements(uuid)');
  oid_usage := to_regprocedure('growth.record_usage(uuid,text,bigint)');
  oid_subscription := to_regprocedure('growth.set_workspace_subscription(uuid,text,text,text,text)');
  oid_enterprise := to_regprocedure('growth.set_enterprise_policy(uuid,integer,text,text)');

  IF oid_entitlements IS NULL OR oid_usage IS NULL OR oid_subscription IS NULL OR oid_enterprise IS NULL THEN
    RAISE EXCEPTION '055 failed: commercial helper is missing';
  END IF;

  SELECT string_agg(pg_get_functiondef(p.oid), E'\n')
    INTO definition
    FROM pg_proc p
   WHERE p.oid IN (oid_entitlements, oid_usage, oid_subscription, oid_enterprise);

  IF position('monthly_action_limit' IN lower(definition)) = 0
     OR position('record_usage' IN lower(definition)) = 0
     OR position('subscription management requires owner or admin' IN lower(definition)) = 0
     OR position('enterprise policy requires owner or admin' IN lower(definition)) = 0
     OR position('provider_customer_ref' IN lower(definition)) = 0
  THEN
    RAISE EXCEPTION '055 failed: commercial controls are incomplete';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO owner_name, is_definer
    FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
   WHERE p.oid = oid_entitlements;
  IF owner_name <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '055 failed: commercial owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', oid_entitlements, 'EXECUTE')
    INTO app_execute;
  SELECT has_function_privilege('public', oid_entitlements, 'EXECUTE')
    INTO public_execute;
  SELECT has_table_privilege('app_runtime', 'growth.workspace_subscriptions', 'SELECT')
    INTO direct_sub_select;
  SELECT has_table_privilege('app_runtime', 'growth.usage_counters', 'SELECT')
    INTO direct_usage_select;
  SELECT c.relrowsecurity
    INTO rls_sub
    FROM pg_class c
   WHERE c.oid = 'growth.workspace_subscriptions'::regclass;
  SELECT c.relforcerowsecurity
    INTO rls_enterprise
    FROM pg_class c
   WHERE c.oid = 'growth.enterprise_policies'::regclass;

  IF app_execute IS DISTINCT FROM true OR public_execute IS DISTINCT FROM false
     OR direct_sub_select IS DISTINCT FROM false
     OR direct_usage_select IS DISTINCT FROM false
     OR rls_sub IS DISTINCT FROM true
     OR rls_enterprise IS DISTINCT FROM true
  THEN
    RAISE EXCEPTION '055 failed: commercial privilege/RLS boundary';
  END IF;

  -- Behavioral quota proof: a first use in a new month must not bypass the
  -- free-plan limit just because no usage_counters row exists yet.
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);

  DELETE FROM growth.usage_counters
   WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001'::uuid
     AND period_start = date_trunc('month', now())
     AND metric_key = 'automation_requests';

  limit_blocked := false;
  BEGIN
    PERFORM growth.record_usage(
      'b0000000-0000-4000-8000-000000000001'::uuid,
      'automation_requests',
      101
    );
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM = 'commercial entitlement limit reached' THEN
      limit_blocked := true;
    ELSE
      RAISE;
    END IF;
  END;

  IF limit_blocked IS DISTINCT FROM true THEN
    RAISE EXCEPTION '055 failed: first-use free-plan quota bypassed';
  END IF;

  SELECT r.used_units
    INTO usage_after
    FROM growth.record_usage(
      'b0000000-0000-4000-8000-000000000001'::uuid,
      'automation_requests',
      100
    ) AS r;

  IF usage_after IS DISTINCT FROM 100 THEN
    RAISE EXCEPTION '055 failed: valid first-use quota increment was not recorded';
  END IF;

  limit_blocked := false;
  BEGIN
    PERFORM growth.record_usage(
      'b0000000-0000-4000-8000-000000000001'::uuid,
      'automation_requests',
      1
    );
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM = 'commercial entitlement limit reached' THEN
      limit_blocked := true;
    ELSE
      RAISE;
    END IF;
  END;

  IF limit_blocked IS DISTINCT FROM true THEN
    RAISE EXCEPTION '055 failed: subsequent free-plan quota overflow was allowed';
  END IF;
END;
$commercial_gate$;

ROLLBACK;

SELECT 'TEST-055 PASS: commercial entitlements and enterprise governance' AS result;
