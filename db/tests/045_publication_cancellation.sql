-- Publication cancellation contract gate.
-- Proves the cancellation boundary is actor-bound and fail-closed.
\set ON_ERROR_STOP on

BEGIN;

DO $cancel_gate$
DECLARE
  cancel_oid oid;
  cancel_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
BEGIN
  cancel_oid := to_regprocedure('growth.cancel_publication_intent(uuid,uuid,uuid)');
  IF cancel_oid IS NULL THEN
    RAISE EXCEPTION '045 failed: cancellation helper is missing';
  END IF;

  SELECT pg_get_functiondef(cancel_oid) INTO cancel_def;
  IF position('security definer' IN lower(cancel_def)) = 0
     OR position('sending' IN lower(cancel_def)) = 0
     OR position('confirmed' IN lower(cancel_def)) = 0
     OR position('cancelled_by' IN lower(cancel_def)) = 0
     OR position('app.user_id' IN lower(cancel_def)) = 0
  THEN
    RAISE EXCEPTION '045 failed: cancellation helper lacks actor/state guards';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = cancel_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '045 failed: cancellation helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', cancel_oid, 'EXECUTE')
    INTO app_execute;
  IF app_execute IS DISTINCT FROM true THEN
    RAISE EXCEPTION '045 failed: app_runtime cannot execute cancellation helper';
  END IF;

  SELECT has_function_privilege('public', cancel_oid, 'EXECUTE')
    INTO public_execute;
  IF public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION '045 failed: PUBLIC can execute cancellation helper';
  END IF;
END;
$cancel_gate$;

ROLLBACK;

SELECT 'TEST-045 PASS: publication cancellation contract' AS result;
