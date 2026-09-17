-- Growth OS — identity runtime table privilege and RLS gate.
-- Proves workspace discovery for the authenticated user and rejection of a
-- forged workspace context through the same app_runtime role used by the API.

\set ON_ERROR_STOP on

BEGIN;
SET search_path = growth, public;

DO $$
DECLARE
  insecure_table_count integer;
BEGIN
  SELECT count(*)::integer
    INTO insecure_table_count
  FROM pg_class table_row
  JOIN pg_namespace schema_row ON schema_row.oid = table_row.relnamespace
  WHERE schema_row.nspname = 'growth'
    AND table_row.relname IN ('workspaces', 'memberships')
    AND (NOT table_row.relrowsecurity OR NOT table_row.relforcerowsecurity);

  IF insecure_table_count <> 0 THEN
    RAISE EXCEPTION 'TEST FAIL: identity tables require RLS + FORCE RLS';
  END IF;

  IF NOT has_table_privilege('app_runtime', 'growth.workspaces', 'SELECT')
     OR NOT has_table_privilege('app_runtime', 'growth.memberships', 'SELECT')
     OR NOT has_table_privilege('app_runtime', 'growth.memberships', 'UPDATE')
  THEN
    RAISE EXCEPTION 'TEST FAIL: identity runtime table privileges are incomplete';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.workspaces', 'UPDATE') THEN
    RAISE EXCEPTION 'TEST FAIL: app_runtime must not update workspaces directly';
  END IF;
END $$;

SELECT set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', false);
SELECT set_config('app.workspace_id', '', false);

SET ROLE app_runtime;

SELECT count(*) = 2 AS owner_memberships_visible
FROM growth.memberships
WHERE user_id = 'a0000000-0000-4000-8000-000000000001'
  AND status = 'active'
\gset

SELECT count(*) = 2 AS owner_workspaces_visible
FROM growth.workspaces
WHERE status = 'active'
\gset

RESET ROLE;

\if :owner_memberships_visible
\else
  \echo 'TEST FAIL: authenticated owner cannot discover active memberships'
  \quit 1
\endif

\if :owner_workspaces_visible
\else
  \echo 'TEST FAIL: authenticated owner cannot discover active workspaces'
  \quit 1
\endif

SELECT set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', false);
SELECT set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', false);

SET ROLE app_runtime;

SELECT count(*) = 0 AS forged_memberships_hidden
FROM growth.memberships
WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001'
\gset

SELECT count(*) = 0 AS forged_workspace_hidden
FROM growth.workspaces
WHERE id = 'b0000000-0000-4000-8000-000000000001'
\gset

UPDATE growth.memberships
SET role = 'viewer'
WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001'
  AND user_id = 'a0000000-0000-4000-8000-000000000001';

RESET ROLE;

\if :forged_memberships_hidden
\else
  \echo 'TEST FAIL: forged workspace exposed membership rows'
  \quit 1
\endif

\if :forged_workspace_hidden
\else
  \echo 'TEST FAIL: forged workspace exposed the workspace row'
  \quit 1
\endif

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM growth.memberships
    WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001'
      AND user_id = 'a0000000-0000-4000-8000-000000000001'
      AND role = 'owner'
  ) THEN
    RAISE EXCEPTION 'TEST FAIL: forged workspace changed the victim membership';
  END IF;
END $$;

ROLLBACK;

\echo 'PASS: identity runtime grants preserve authenticated discovery and cross-workspace isolation'
