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

SELECT set_config(
  'test.owner_memberships_visible',
  (count(*) = 2)::text,
  true
)
FROM growth.memberships
WHERE user_id = 'a0000000-0000-4000-8000-000000000001'
  AND status = 'active';

SELECT set_config(
  'test.owner_workspaces_visible',
  (count(*) = 2)::text,
  true
)
FROM growth.workspaces
WHERE status = 'active';

RESET ROLE;

SELECT set_config('app.user_id', 'a0000000-0000-4000-8000-000000000002', false);
SELECT set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', false);

SET ROLE app_runtime;

SELECT set_config(
  'test.forged_memberships_hidden',
  (count(*) = 0)::text,
  true
)
FROM growth.memberships
WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001';

SELECT set_config(
  'test.forged_workspace_hidden',
  (count(*) = 0)::text,
  true
)
FROM growth.workspaces
WHERE id = 'b0000000-0000-4000-8000-000000000001';

UPDATE growth.memberships
SET role = 'viewer'
WHERE workspace_id = 'b0000000-0000-4000-8000-000000000001'
  AND user_id = 'a0000000-0000-4000-8000-000000000001';

RESET ROLE;

DO $$
BEGIN
  IF NOT current_setting('test.owner_memberships_visible')::boolean
     OR NOT current_setting('test.owner_workspaces_visible')::boolean
     OR NOT current_setting('test.forged_memberships_hidden')::boolean
     OR NOT current_setting('test.forged_workspace_hidden')::boolean
  THEN
    RAISE EXCEPTION 'TEST FAIL: identity runtime visibility or isolation assertion failed';
  END IF;

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
