-- Publication retry scheduling contract gate.
-- Proves the durable retry boundary is narrow and least-privileged.
\set ON_ERROR_STOP on

BEGIN;

DO $retry_gate$
DECLARE
  retry_oid oid;
  retry_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  has_retry_count boolean;
  has_error_class boolean;
BEGIN
  retry_oid := to_regprocedure(
    'growth.schedule_publication_retry(uuid,uuid,integer,timestamptz,text)'
  );
  IF retry_oid IS NULL THEN
    RAISE EXCEPTION '044 failed: retry scheduling helper is missing';
  END IF;

  SELECT pg_get_functiondef(retry_oid) INTO retry_def;
  IF position('security definer' IN lower(retry_def)) = 0
     OR position('failed_retryable' IN lower(retry_def)) = 0
     OR position('needs_user_action' IN lower(retry_def)) = 0
     OR position('retry_count' IN lower(retry_def)) = 0
  THEN
    RAISE EXCEPTION '044 failed: retry helper lacks guarded state transitions';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = retry_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '044 failed: retry helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', retry_oid, 'EXECUTE')
    INTO app_execute;
  IF app_execute IS DISTINCT FROM true THEN
    RAISE EXCEPTION '044 failed: app_runtime cannot execute retry helper';
  END IF;

  SELECT has_function_privilege('public', retry_oid, 'EXECUTE')
    INTO public_execute;
  IF public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION '044 failed: PUBLIC can execute retry helper';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'growth.publication_intents'::regclass
      AND attname = 'retry_count'
      AND NOT attisdropped
  ) INTO has_retry_count;
  SELECT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'growth.publication_intents'::regclass
      AND attname = 'last_error_class'
      AND NOT attisdropped
  ) INTO has_error_class;

  IF NOT has_retry_count OR NOT has_error_class THEN
    RAISE EXCEPTION '044 failed: retry audit columns are missing';
  END IF;
END;
$retry_gate$;

ROLLBACK;

SELECT 'TEST-044 PASS: publication retry scheduling contract' AS result;
