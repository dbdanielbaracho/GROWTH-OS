-- Growth OS Identity v1 — privileged role bootstrap.
--
-- Execute with the provider-native administrative identity before migration 006.
-- This role owns only the narrow SECURITY DEFINER identity functions introduced
-- by 006. It is never granted to app_runtime or growth_migrator.

\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_identity_helper') THEN
    CREATE ROLE growth_identity_helper
      NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS;
  END IF;
END $$;
