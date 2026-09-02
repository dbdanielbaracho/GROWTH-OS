-- Usage: psql -v runtime_role='growth_app_runtime' -f tests/002_runtime_role_gate.sql
\set ON_ERROR_STOP on
SELECT CASE WHEN rolsuper THEN 'true' ELSE 'false' END AS runtime_super,
       CASE WHEN rolbypassrls THEN 'true' ELSE 'false' END AS runtime_bypass
FROM pg_roles WHERE rolname=:'runtime_role';
\gset
\if :runtime_super
  \echo 'FAIL: runtime role is superuser'
  SELECT 1 / 0;
\endif
\if :runtime_bypass
  \echo 'FAIL: runtime role has BYPASSRLS'
  SELECT 1 / 0;
\endif

SELECT CASE WHEN count(*) > 0 THEN 'true' ELSE 'false' END AS owns_tenant_tables
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_roles r ON r.oid=c.relowner
WHERE n.nspname='growth' AND c.relkind='r' AND r.rolname=:'runtime_role';
\gset
\if :owns_tenant_tables
  \echo 'FAIL: runtime role owns growth tables'
  SELECT 1 / 0;
\endif

-- Internal cross-tenant worker queue must never be directly accessible by normal API runtime role.
SELECT CASE WHEN
  has_table_privilege(:'runtime_role','growth.jobs','SELECT') OR
  has_table_privilege(:'runtime_role','growth.jobs','INSERT') OR
  has_table_privilege(:'runtime_role','growth.jobs','UPDATE') OR
  has_table_privilege(:'runtime_role','growth.jobs','DELETE')
THEN 'true' ELSE 'false' END AS jobs_access;
\gset
\if :jobs_access
  \echo 'FAIL: normal API runtime role has direct access to internal growth.jobs'
  SELECT 1 / 0;
\endif

\echo 'PASS: runtime role gate'
