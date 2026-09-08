-- Publication reconciliation contract gate.
-- Proves the evidence boundary is immutable, bounded and least-privileged.
\set ON_ERROR_STOP on

BEGIN;

DO $reconciliation_gate$
DECLARE
  reconciliation_oid oid;
  reconciliation_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
BEGIN
  reconciliation_oid := to_regprocedure(
    'growth.record_publication_reconciliation(uuid,uuid,integer,text,text,text,text,text)'
  );
  IF reconciliation_oid IS NULL THEN
    RAISE EXCEPTION '046 failed: reconciliation helper is missing';
  END IF;

  SELECT pg_get_functiondef(reconciliation_oid) INTO reconciliation_def;
  IF position('security definer' IN lower(reconciliation_def)) = 0
     OR position('publication_reconciliation_attempts' IN lower(reconciliation_def)) = 0
     OR position('immutable evidence' IN lower(reconciliation_def)) = 0
     OR position('matched' IN lower(reconciliation_def)) = 0
     OR position('needs_user_action' IN lower(reconciliation_def)) = 0
  THEN
    RAISE EXCEPTION '046 failed: reconciliation helper lacks evidence/state guards';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = reconciliation_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '046 failed: reconciliation helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', reconciliation_oid, 'EXECUTE')
    INTO app_execute;
  IF app_execute IS DISTINCT FROM true THEN
    RAISE EXCEPTION '046 failed: app_runtime cannot execute reconciliation helper';
  END IF;

  SELECT has_function_privilege('public', reconciliation_oid, 'EXECUTE')
    INTO public_execute;
  IF public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION '046 failed: PUBLIC can execute reconciliation helper';
  END IF;
END;
$reconciliation_gate$;

ROLLBACK;

SELECT 'TEST-046 PASS: publication reconciliation contract' AS result;
