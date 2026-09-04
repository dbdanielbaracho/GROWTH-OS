-- Issue #24 regression gate: production identity adapter DB support.
-- Run after migration 009 on the isolated validation cluster.
\set ON_ERROR_STOP on

DO $$
DECLARE
  fn regprocedure;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'growth.identity_touch_session(uuid,timestamp with time zone)'::regprocedure,
    'growth.identity_begin_login_attempt(text,inet,text,interval,integer,integer)'::regprocedure,
    'growth.identity_complete_login_attempt(uuid)'::regprocedure,
    'growth.identity_upgrade_password_hash(uuid,text,smallint)'::regprocedure
  ] LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_proc p
      WHERE p.oid = fn
        AND pg_get_userbyid(p.proowner) = 'growth_identity_helper'
        AND p.prosecdef
    ) THEN
      RAISE EXCEPTION '028 failed: % must be SECURITY DEFINER owned by growth_identity_helper', fn;
    END IF;

    IF has_function_privilege('public', fn::text, 'EXECUTE') THEN
      RAISE EXCEPTION '028 failed: PUBLIC retains EXECUTE on %', fn;
    END IF;

    IF NOT has_function_privilege('app_runtime', fn::text, 'EXECUTE') THEN
      RAISE EXCEPTION '028 failed: app_runtime lacks EXECUTE on %', fn;
    END IF;
  END LOOP;

  IF has_table_privilege('app_runtime', 'growth.sessions', 'SELECT')
     OR has_table_privilege('app_runtime', 'growth.sessions', 'INSERT')
     OR has_table_privilege('app_runtime', 'growth.sessions', 'UPDATE')
     OR has_table_privilege('app_runtime', 'growth.sessions', 'DELETE') THEN
    RAISE EXCEPTION '028 failed: app_runtime received direct sessions table privileges';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.login_attempts', 'SELECT')
     OR has_table_privilege('app_runtime', 'growth.login_attempts', 'INSERT')
     OR has_table_privilege('app_runtime', 'growth.login_attempts', 'UPDATE')
     OR has_table_privilege('app_runtime', 'growth.login_attempts', 'DELETE') THEN
    RAISE EXCEPTION '028 failed: app_runtime received direct login_attempts table privileges';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.password_credentials', 'SELECT')
     OR has_table_privilege('app_runtime', 'growth.password_credentials', 'INSERT')
     OR has_table_privilege('app_runtime', 'growth.password_credentials', 'UPDATE')
     OR has_table_privilege('app_runtime', 'growth.password_credentials', 'DELETE') THEN
    RAISE EXCEPTION '028 failed: app_runtime received direct password_credentials table privileges';
  END IF;
END $$;

SELECT 'PASS: Issue #24 production identity adapter helpers are narrow and secret tables remain closed' AS result;
