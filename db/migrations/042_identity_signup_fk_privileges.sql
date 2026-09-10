-- Growth OS Identity v1.3 — complete the signup helper's FK privileges.
-- PostgreSQL foreign-key enforcement for password_credentials requires the
-- SECURITY DEFINER owner to have REFERENCES on the referenced identity tables.
-- Keep the grant on the narrow helper role; app_runtime still receives no
-- direct table access to credential-bearing rows.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_identity_helper') THEN
    RAISE EXCEPTION 'growth_identity_helper is required';
  END IF;
END $$;

GRANT USAGE ON SCHEMA growth TO growth_identity_helper;
GRANT SELECT, INSERT, UPDATE, REFERENCES ON
  growth.users,
  growth.auth_identities,
  growth.password_credentials,
  growth.email_verifications,
  growth.audit_events
TO growth_identity_helper;

DO $$
BEGIN
  IF NOT has_schema_privilege('growth_identity_helper', 'growth', 'USAGE') THEN
    RAISE EXCEPTION 'identity helper cannot use growth schema';
  END IF;
  IF NOT has_table_privilege(
    'growth_identity_helper',
    'growth.users',
    'REFERENCES'
  ) THEN
    RAISE EXCEPTION 'identity helper cannot reference growth.users';
  END IF;
  IF NOT has_table_privilege(
    'growth_identity_helper',
    'growth.auth_identities',
    'REFERENCES'
  ) THEN
    RAISE EXCEPTION 'identity helper cannot reference growth.auth_identities';
  END IF;
  IF NOT has_table_privilege(
    'growth_identity_helper',
    'growth.password_credentials',
    'INSERT'
  ) THEN
    RAISE EXCEPTION 'identity helper cannot insert password credentials';
  END IF;
END $$;

COMMIT;
