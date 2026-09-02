-- Growth OS Identity v1 — catalog, privilege and secret-surface gate.

\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  missing_tables text[];
  rls_failures integer;
  leaked_columns integer;
  helper_memberships integer;
BEGIN
  SELECT array_agg(expected ORDER BY expected) INTO missing_tables
  FROM unnest(ARRAY[
    'auth_identities','password_credentials','email_verifications','password_resets',
    'mfa_factors','mfa_recovery_codes','sessions','invitations','login_attempts'
  ]) expected
  WHERE to_regclass('growth.' || expected) IS NULL;
  IF missing_tables IS NOT NULL THEN
    RAISE EXCEPTION 'TEST FAIL: missing Identity v1 tables: %', missing_tables;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='growth' AND table_name='users' AND column_name='email_verified_at'
      AND data_type='timestamp with time zone'
  ) THEN
    RAISE EXCEPTION 'TEST FAIL: growth.users.email_verified_at is absent or wrong type';
  END IF;

  SELECT count(*) INTO rls_failures
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='growth'
    AND c.relname=ANY(ARRAY[
      'auth_identities','password_credentials','email_verifications','password_resets',
      'mfa_factors','mfa_recovery_codes','sessions','invitations'
    ])
    AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity);
  IF rls_failures <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL: % Identity v1 table(s) lack ENABLE+FORCE RLS', rls_failures;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='growth' AND c.relname='login_attempts' AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'TEST FAIL: login_attempts must use the documented helper-only exception, not caller RLS';
  END IF;

  SELECT count(*) INTO leaked_columns
  FROM information_schema.columns
  WHERE table_schema='growth'
    AND table_name=ANY(ARRAY[
      'auth_identities','password_credentials','email_verifications','password_resets',
      'mfa_factors','mfa_recovery_codes','sessions','invitations'
    ])
    AND column_name IN ('token','session_token','password','recovery_code','totp_secret');
  IF leaked_columns <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL: plaintext secret/token column names found: %', leaked_columns;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname='growth_identity_helper' AND (rolcanlogin OR NOT rolbypassrls)
  ) OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='growth_identity_helper') THEN
    RAISE EXCEPTION 'TEST FAIL: growth_identity_helper must be NOLOGIN+BYPASSRLS';
  END IF;

  SELECT count(*) INTO helper_memberships
  FROM pg_auth_members am
  JOIN pg_roles granted ON granted.oid=am.roleid
  JOIN pg_roles member ON member.oid=am.member
  WHERE granted.rolname='growth_identity_helper'
    AND member.rolname IN ('app_runtime','growth_migrator');
  IF helper_memberships <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL: helper role was granted to an application/migration role';
  END IF;

  RAISE NOTICE 'PASS: Identity v1 catalog, RLS and helper-role isolation are present';
END $$;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'auth_identities','password_credentials','email_verifications','password_resets',
    'mfa_factors','mfa_recovery_codes','sessions','invitations','login_attempts'
  ] LOOP
    IF has_table_privilege('app_runtime','growth.'||t,'SELECT')
       OR has_table_privilege('app_runtime','growth.'||t,'INSERT')
       OR has_table_privilege('app_runtime','growth.'||t,'UPDATE')
       OR has_table_privilege('app_runtime','growth.'||t,'DELETE') THEN
      RAISE EXCEPTION 'TEST FAIL: app_runtime has direct DML privilege on growth.%', t;
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS: app_runtime has no direct DML on Identity v1 tables';
END $$;

DO $$
DECLARE
  f regprocedure;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'growth.identity_signup(text,text,smallint)'::regprocedure,
    'growth.identity_lookup_password(text)'::regprocedure,
    'growth.identity_record_login_attempt(text,boolean,inet,text)'::regprocedure,
    'growth.identity_issue_email_verification(text,timestamptz)'::regprocedure,
    'growth.identity_consume_email_verification(text)'::regprocedure,
    'growth.identity_request_password_reset(text,text,timestamptz,inet,text)'::regprocedure,
    'growth.identity_complete_password_reset(text,text,smallint)'::regprocedure,
    'growth.identity_create_session(uuid,text,text[],timestamptz,timestamptz,inet,text)'::regprocedure,
    'growth.identity_resolve_session(text)'::regprocedure,
    'growth.identity_revoke_session(uuid,text)'::regprocedure,
    'growth.identity_revoke_all_sessions()'::regprocedure,
    'growth.identity_create_workspace(text,text,text,text)'::regprocedure,
    'growth.identity_issue_invitation(uuid,text,text,boolean,text,timestamptz)'::regprocedure,
    'growth.identity_revoke_invitation(uuid)'::regprocedure,
    'growth.identity_accept_invitation(text)'::regprocedure,
    'growth.identity_account_audit(integer)'::regprocedure
  ] LOOP
    IF NOT has_function_privilege('app_runtime',f,'EXECUTE') THEN
      RAISE EXCEPTION 'TEST FAIL: app_runtime lacks EXECUTE on %', f;
    END IF;
    IF has_function_privilege('public',f,'EXECUTE') THEN
      RAISE EXCEPTION 'TEST FAIL: PUBLIC can execute %', f;
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS: public database API grants are explicit and PUBLIC is revoked';
END $$;

DO $$
DECLARE caught_sqlstate text;
BEGIN
  SET ROLE app_runtime;
  BEGIN
    PERFORM * FROM growth.password_credentials LIMIT 1;
    RAISE EXCEPTION 'TEST FAIL: app_runtime directly read password_credentials';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate=RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  IF caught_sqlstate <> '42501' THEN
    RAISE EXCEPTION 'TEST FAIL: direct credential read returned %, expected 42501',caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS: direct credential read is physically denied (42501)';
END $$;

\echo 'PASS: Identity v1 schema and security gate'
