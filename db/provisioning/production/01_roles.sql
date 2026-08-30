-- Growth OS RC9 — Production role bootstrap.
-- Must be executed once, by the provider's native administrative identity
-- (RDS master user, Crunchy Bridge admin, Neon default role, or a local
-- superuser in disposable test environments). This script never assumes
-- CREATEROLE on growth_migrator itself; role creation is a one-time
-- administrative act, not a migration-time capability.
--
-- Idempotent: safe to re-run against an environment where roles already exist.

\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_migrator') THEN
    CREATE ROLE growth_migrator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime') THEN
    CREATE ROLE app_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;
END $$;

-- The canonical DDL itself issues CREATE SCHEMA IF NOT EXISTS for growth and
-- aggregate_intelligence, so growth_migrator needs database-level CREATE to
-- run it, not schema-level privilege on schemas that do not exist yet.
-- PostgreSQL 15+ no longer grants CREATE on a fresh database to PUBLIC by
-- default, so this must be explicit.
DO $$
BEGIN
  EXECUTE format('GRANT CREATE ON DATABASE %I TO growth_migrator', current_database());
END $$;
