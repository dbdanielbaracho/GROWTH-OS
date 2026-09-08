-- Publication execution context contract gate.
-- Proves the worker context is a narrow SECURITY DEFINER boundary.
\set ON_ERROR_STOP on

BEGIN;

DO $execution_context$
DECLARE
  context_oid oid;
  context_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  direct_credentials boolean;
  direct_intents boolean;
BEGIN
  context_oid := to_regprocedure(
    'growth.get_publication_execution_context(uuid,uuid,uuid)'
  );
  IF context_oid IS NULL THEN
    RAISE EXCEPTION '043 failed: execution context helper is missing';
  END IF;

  SELECT pg_get_functiondef(context_oid) INTO context_def;
  IF position('security definer' IN lower(context_def)) = 0
     OR position('provider_credentials' IN lower(context_def)) = 0
     OR position('media_assets' IN lower(context_def)) = 0
     OR position('claim_token' IN lower(context_def)) = 0
  THEN
    RAISE EXCEPTION '043 failed: helper does not expose the required protected context';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = context_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '043 failed: helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', context_oid, 'EXECUTE')
    INTO app_execute;
  IF app_execute IS DISTINCT FROM true THEN
    RAISE EXCEPTION '043 failed: app_runtime cannot execute context helper';
  END IF;

  SELECT has_function_privilege('public', context_oid, 'EXECUTE')
    INTO public_execute;
  IF public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION '043 failed: PUBLIC can execute context helper';
  END IF;

  SELECT has_table_privilege('app_runtime','growth.provider_credentials','SELECT')
    INTO direct_credentials;
  SELECT has_table_privilege('app_runtime','growth.publication_intents','SELECT')
    INTO direct_intents;

  IF direct_credentials IS DISTINCT FROM false
     OR direct_intents IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '043 failed: runtime received direct publication credential/table access';
  END IF;
END;
$execution_context$;

ROLLBACK;

\echo 'PASS 043_publication_execution_context'
