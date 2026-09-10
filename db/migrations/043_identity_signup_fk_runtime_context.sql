-- Growth OS Identity v1.4 — complete FK checks for every signup runtime context.
-- RI trigger checks may execute under the invoking/runtime or table-owner role,
-- not only the SECURITY DEFINER function owner. Grant only schema usage and
-- REFERENCES; do not grant app_runtime direct access to credential rows.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_identity_helper')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_migrator') THEN
    RAISE EXCEPTION 'identity runtime roles are required';
  END IF;
END $$;

GRANT USAGE ON SCHEMA growth
  TO app_runtime, growth_identity_helper, growth_migrator;

GRANT REFERENCES ON
  growth.users,
  growth.auth_identities
TO app_runtime, growth_identity_helper, growth_migrator;

DO $$
DECLARE
  role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY[
    'app_runtime', 'growth_identity_helper', 'growth_migrator'
  ] LOOP
    IF NOT has_schema_privilege(role_name, 'growth', 'USAGE') THEN
      RAISE EXCEPTION '% cannot use growth schema', role_name;
    END IF;
    IF NOT has_table_privilege(role_name, 'growth.auth_identities', 'REFERENCES') THEN
      RAISE EXCEPTION '% cannot reference growth.auth_identities', role_name;
    END IF;
  END LOOP;
END $$;

COMMIT;
