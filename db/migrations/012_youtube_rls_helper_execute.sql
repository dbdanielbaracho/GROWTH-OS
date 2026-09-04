-- Growth OS — YouTube connector RLS helper dependency (Issue #26).
--
-- Forward-only migration. Preserves 001-011 byte-for-byte.
--
-- Physical validation of youtube_complete_authorization() on the isolated
-- growth_os_test cluster exposed a real privilege edge:
--
--   permission denied for function workspace_row_visible
--
-- The YouTube adapter helpers are SECURITY DEFINER functions owned by
-- growth_migrator. During tenant-scoped writes they traverse FORCE-RLS tenant
-- tables. The workspaces SELECT policy delegates membership visibility to
-- growth.workspace_row_visible(uuid), a SECURITY DEFINER predicate owned by
-- growth_rls_helper. Migration 002 intentionally granted that predicate only
-- to app_runtime because, at that time, no growth_migrator-owned code path
-- needed to invoke it. Migration 010 introduced such a path.
--
-- This migration grants only EXECUTE on that single boolean RLS predicate to
-- growth_migrator. It grants no table privilege, no BYPASSRLS attribute, no
-- role membership, and no ownership change. app_runtime and PUBLIC boundaries
-- remain unchanged.

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  fn regprocedure := 'growth.workspace_row_visible(uuid)'::regprocedure;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='growth_migrator') THEN
    RAISE EXCEPTION '012 requires growth_migrator role';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='growth_rls_helper') THEN
    RAISE EXCEPTION '012 requires growth_rls_helper role';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid=fn
      AND pg_get_userbyid(p.proowner)='growth_rls_helper'
      AND p.prosecdef
  ) THEN
    RAISE EXCEPTION '012 requires workspace_row_visible(uuid) to remain SECURITY DEFINER owned by growth_rls_helper';
  END IF;

  IF has_function_privilege('public',fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '012 refuses to proceed while PUBLIC can execute workspace_row_visible(uuid)';
  END IF;

  IF NOT has_function_privilege('app_runtime',fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '012 refuses to alter the established app_runtime workspace-row predicate boundary';
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION growth.workspace_row_visible(uuid) TO growth_migrator;

COMMIT;
