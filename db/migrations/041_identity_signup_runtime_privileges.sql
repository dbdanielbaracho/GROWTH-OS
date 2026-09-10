-- Growth OS Identity v1.2 — restore the reviewed runtime privilege boundary.
-- The signup function is SECURITY DEFINER, but production must still retain
-- explicit EXECUTE/schema/table grants after role or migration provisioning.
-- This migration is idempotent and fails closed if the required roles/functions
-- are missing.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_identity_helper') THEN
    RAISE EXCEPTION 'identity runtime roles are required';
  END IF;
  IF to_regprocedure('growth.identity_signup(text,text,smallint)') IS NULL
     OR to_regprocedure('growth.identity_signup_with_verification(text,text,smallint,text,timestamptz)') IS NULL THEN
    RAISE EXCEPTION 'identity signup functions are required';
  END IF;
END $$;

GRANT USAGE ON SCHEMA growth TO app_runtime, growth_identity_helper;

GRANT SELECT, INSERT, UPDATE ON
  growth.users,
  growth.auth_identities,
  growth.password_credentials,
  growth.email_verifications,
  growth.audit_events
TO growth_identity_helper;

GRANT EXECUTE ON FUNCTION growth.identity_signup(text,text,smallint)
  TO app_runtime, growth_identity_helper;
GRANT EXECUTE ON FUNCTION growth.identity_signup_with_verification(
  text,text,smallint,text,timestamptz
) TO app_runtime;

DO $$
BEGIN
  IF NOT has_function_privilege(
    'app_runtime',
    'growth.identity_signup_with_verification(text,text,smallint,text,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'app_runtime cannot execute identity signup';
  END IF;
  IF NOT has_table_privilege(
    'growth_identity_helper',
    'growth.email_verifications',
    'INSERT'
  ) THEN
    RAISE EXCEPTION 'identity helper cannot insert email verifications';
  END IF;
END $$;

COMMIT;
