-- Growth OS RC9 — Security Policy Fix regression suite.
-- Closes RC9-FINDING-001 and RC9-FINDING-003. Every assertion here was
-- physically proven at least once during the design/hardening rounds
-- before being encoded as a permanent, versioned test.
--
-- Must start as an administrative identity. The three connection URLs are
-- read from the environment so the same test runs locally and on hosted
-- PostgreSQL without assuming a database name, host, port, or shared password:
--   APP_RUNTIME_DATABASE_URL, MIGRATOR_DATABASE_URL, ADMIN_DATABASE_URL.

\set ON_ERROR_STOP on
\getenv app_runtime_url APP_RUNTIME_DATABASE_URL
\getenv migrator_url MIGRATOR_DATABASE_URL
\getenv admin_url ADMIN_DATABASE_URL

\if :{?app_runtime_url}
\else
  \echo 'TEST FAIL: APP_RUNTIME_DATABASE_URL is required'
  SELECT 1 / 0;
\endif
\if :{?migrator_url}
\else
  \echo 'TEST FAIL: MIGRATOR_DATABASE_URL is required'
  SELECT 1 / 0;
\endif
\if :{?admin_url}
\else
  \echo 'TEST FAIL: ADMIN_DATABASE_URL is required'
  SELECT 1 / 0;
\endif

SET search_path = growth, public;

-- ============================================================
-- Part 1: growth_rls_helper role attributes and isolation.
-- ============================================================
DO $$
DECLARE
  r record;
BEGIN
  SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolbypassrls
    INTO r FROM pg_roles WHERE rolname = 'growth_rls_helper';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TEST FAIL: growth_rls_helper role does not exist';
  END IF;
  IF r.rolcanlogin THEN RAISE EXCEPTION 'TEST FAIL: growth_rls_helper must be NOLOGIN'; END IF;
  IF r.rolsuper THEN RAISE EXCEPTION 'TEST FAIL: growth_rls_helper must be NOSUPERUSER'; END IF;
  IF r.rolcreatedb THEN RAISE EXCEPTION 'TEST FAIL: growth_rls_helper must be NOCREATEDB'; END IF;
  IF r.rolcreaterole THEN RAISE EXCEPTION 'TEST FAIL: growth_rls_helper must be NOCREATEROLE'; END IF;
  IF NOT r.rolbypassrls THEN RAISE EXCEPTION 'TEST FAIL: growth_rls_helper must have BYPASSRLS'; END IF;

  RAISE NOTICE 'PASS: growth_rls_helper attributes correct (NOLOGIN, NOSUPERUSER, NOCREATEDB, NOCREATEROLE, BYPASSRLS)';
END $$;

DO $$
DECLARE
  member_count int;
BEGIN
  SELECT count(*) INTO member_count FROM pg_auth_members WHERE roleid = 'growth_rls_helper'::regrole;
  IF member_count <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL: growth_rls_helper has % member(s), expected zero', member_count;
  END IF;
  RAISE NOTICE 'PASS: growth_rls_helper has zero memberships';
END $$;

-- ============================================================
-- SET ROLE denial — physically attempted, verified via psql \if with a
-- genuine boolean captured by SQL comparison (psql does not substitute
-- :variables inside $$-quoted DO block bodies, so the check must live
-- outside any DO block).
-- ============================================================
\c :app_runtime_url
\set ON_ERROR_STOP off
SET ROLE growth_rls_helper;
\set ON_ERROR_STOP on
SELECT (current_user = 'app_runtime') AS still_app_runtime \gset
RESET ROLE;

\c :migrator_url
\set ON_ERROR_STOP off
SET ROLE growth_rls_helper;
\set ON_ERROR_STOP on
SELECT (current_user = 'growth_migrator') AS still_migrator \gset
RESET ROLE;

\c :admin_url
\if :still_app_runtime
  \echo 'PASS: app_runtime cannot SET ROLE growth_rls_helper (remained app_runtime)'
\else
  \echo 'TEST FAIL: app_runtime successfully became growth_rls_helper'
  SELECT 1 / 0;
\endif

\if :still_migrator
  \echo 'PASS: growth_migrator cannot SET ROLE growth_rls_helper (remained growth_migrator)'
\else
  \echo 'TEST FAIL: growth_migrator successfully became growth_rls_helper'
  SELECT 1 / 0;
\endif

-- ============================================================
-- Part 2: function properties.
-- ============================================================
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.proname, ro.rolname AS owner, p.prosecdef, p.proconfig, p.prorettype::regtype AS ret
    FROM pg_proc p JOIN pg_roles ro ON ro.oid = p.proowner
    WHERE p.proname IN ('membership_row_visible','workspace_row_visible')
  LOOP
    IF r.owner <> 'growth_rls_helper' THEN
      RAISE EXCEPTION 'TEST FAIL: % owned by %, expected growth_rls_helper', r.proname, r.owner;
    END IF;
    IF NOT r.prosecdef THEN
      RAISE EXCEPTION 'TEST FAIL: % is not SECURITY DEFINER', r.proname;
    END IF;
    IF r.proconfig IS NULL OR NOT ('search_path=pg_catalog, growth' = ANY(r.proconfig)) THEN
      RAISE EXCEPTION 'TEST FAIL: % does not have a fixed search_path, got %', r.proname, r.proconfig;
    END IF;
    IF r.ret <> 'boolean'::regtype THEN
      RAISE EXCEPTION 'TEST FAIL: % does not return boolean', r.proname;
    END IF;
    RAISE NOTICE 'PASS: % owner/SECURITY DEFINER/search_path/return type correct', r.proname;
  END LOOP;
END $$;

DO $$
DECLARE
  public_grant_count int;
BEGIN
  SELECT count(*) INTO public_grant_count
  FROM information_schema.role_routine_grants
  WHERE routine_name IN ('membership_row_visible','workspace_row_visible')
    AND grantee = 'PUBLIC';
  IF public_grant_count <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL: PUBLIC has EXECUTE on a security helper function';
  END IF;
  RAISE NOTICE 'PASS: PUBLIC has no EXECUTE on either helper function';
END $$;

-- ============================================================
-- Function modification denial — physically attempted, verified by
-- re-reading the function body afterward.
-- ============================================================
\c :app_runtime_url
\set ON_ERROR_STOP off
CREATE OR REPLACE FUNCTION growth.membership_row_visible(p_workspace_id uuid) RETURNS boolean LANGUAGE sql AS $f$ SELECT true; $f$;
\set ON_ERROR_STOP on

\c :migrator_url
\set ON_ERROR_STOP off
CREATE OR REPLACE FUNCTION growth.membership_row_visible(p_workspace_id uuid) RETURNS boolean LANGUAGE sql AS $f$ SELECT true; $f$;
\set ON_ERROR_STOP on

\c :admin_url
SELECT (prosrc = ' SELECT true; ') AS was_replaced, (prosrc ILIKE '%current_app_user_id%') AS looks_original
FROM pg_proc WHERE proname = 'membership_row_visible' \gset

\if :was_replaced
  \echo 'TEST FAIL: membership_row_visible body was replaced by app_runtime or growth_migrator'
  SELECT 1 / 0;
\endif
\if :looks_original
  \echo 'PASS: neither app_runtime nor growth_migrator could replace membership_row_visible (body unchanged, confirmed by re-reading pg_proc)'
\else
  \echo 'TEST FAIL: membership_row_visible body looks unexpectedly different'
  SELECT 1 / 0;
\endif

-- ============================================================
-- Part 3: policies point at the correct functions.
-- ============================================================
DO $$
DECLARE
  mdef text;
  wdef text;
BEGIN
  SELECT pg_get_expr(polqual, polrelid) INTO mdef
  FROM pg_policy WHERE polname = 'memberships_workspace_select';
  IF mdef NOT ILIKE '%membership_row_visible%' THEN
    RAISE EXCEPTION 'TEST FAIL: memberships_workspace_select does not reference membership_row_visible: %', mdef;
  END IF;

  SELECT pg_get_expr(polqual, polrelid) INTO wdef
  FROM pg_policy WHERE polname = 'workspaces_member_select';
  IF wdef NOT ILIKE '%workspace_row_visible%' THEN
    RAISE EXCEPTION 'TEST FAIL: workspaces_member_select does not reference workspace_row_visible: %', wdef;
  END IF;

  RAISE NOTICE 'PASS: both policies reference the correct helper functions';
END $$;

\echo 'PASS: RC9 security policy fix — role, function, and policy structural gates all verified'
