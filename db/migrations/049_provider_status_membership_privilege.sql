-- Growth OS — provider status helper membership read privilege.
-- Production status helpers validate tenant membership through a SECURITY
-- DEFINER chain. Reconcile the minimum table read needed by that helper role.
-- app_runtime remains closed to direct membership reads.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_migrator') THEN
    RAISE EXCEPTION '049 requires growth_migrator role';
  END IF;
END $$;

GRANT SELECT ON growth.memberships TO growth_migrator;

DO $$
BEGIN
  IF NOT has_table_privilege(
    'growth_migrator',
    'growth.memberships',
    'SELECT'
  ) THEN
    RAISE EXCEPTION '049 failed: growth_migrator cannot validate tenant membership';
  END IF;

  IF has_table_privilege(
    'app_runtime',
    'growth.memberships',
    'SELECT'
  ) THEN
    RAISE EXCEPTION '049 failed: app_runtime membership boundary widened';
  END IF;
END $$;

COMMIT;
