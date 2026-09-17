-- Explicit content review submission contract gate.
\set ON_ERROR_STOP on

BEGIN;

DO $content_review_submission_gate$
DECLARE
  helper_oid oid;
  helper_definition text;
  helper_owner text;
  helper_definer boolean;
  table_owner text;
  rls_enabled boolean;
  rls_forced boolean;
  app_execute boolean;
  public_execute boolean;
  app_select boolean;
  app_insert boolean;
BEGIN
  helper_oid := to_regprocedure('growth.content_submit_for_review(uuid,uuid,text)');
  IF helper_oid IS NULL OR to_regclass('growth.content_review_submissions') IS NULL THEN
    RAISE EXCEPTION '067 failed: content review submission contract is missing';
  END IF;

  SELECT lower(pg_get_functiondef(helper_oid)) INTO helper_definition;
  IF position('current_workspace_id' IN helper_definition) = 0
     OR position('tenant_context_valid' IN helper_definition) = 0
     OR position('not exists' IN helper_definition) = 0
     OR position('newer.version_no > cv.version_no' IN helper_definition) = 0
     OR position('expected draft' IN helper_definition) = 0
     OR position('ready_for_review' IN helper_definition) = 0
     OR position('content_review_submissions' IN helper_definition) = 0
  THEN
    RAISE EXCEPTION '067 failed: submission helper lacks tenant/latest-version/lifecycle/audit guards';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, helper_definer
    FROM pg_proc p
    JOIN pg_roles r ON r.oid = p.proowner
   WHERE p.oid = helper_oid;

  SELECT pg_get_userbyid(c.relowner), c.relrowsecurity, c.relforcerowsecurity
    INTO table_owner, rls_enabled, rls_forced
    FROM pg_class c
   WHERE c.oid = 'growth.content_review_submissions'::regclass;

  SELECT has_function_privilege('app_runtime', helper_oid, 'EXECUTE') INTO app_execute;
  SELECT has_function_privilege('public', helper_oid, 'EXECUTE') INTO public_execute;
  SELECT has_table_privilege('app_runtime', 'growth.content_review_submissions', 'SELECT') INTO app_select;
  SELECT has_table_privilege('app_runtime', 'growth.content_review_submissions', 'INSERT') INTO app_insert;

  IF helper_owner <> 'growth_migrator'
     OR helper_definer IS DISTINCT FROM true
     OR table_owner <> 'growth_migrator'
     OR rls_enabled IS DISTINCT FROM true
     OR rls_forced IS DISTINCT FROM true
     OR app_execute IS DISTINCT FROM true
     OR public_execute IS DISTINCT FROM false
     OR app_select IS DISTINCT FROM false
     OR app_insert IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '067 failed: content review submission privileges are not least-privilege';
  END IF;
END;
$content_review_submission_gate$;

ROLLBACK;

SELECT 'TEST-067 PASS: explicit auditable content review submission' AS result;
