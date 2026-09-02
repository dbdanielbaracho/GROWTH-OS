-- Dynamic catalog invariants for Growth OS RC3.
\set ON_ERROR_STOP on
SET search_path = growth, public;

-- A) Any FK whose parent is tenant-owned (has workspace_id) must carry workspace_id on BOTH sides.
WITH fk AS (
  SELECT
    con.conname,
    child.oid AS child_oid,
    parent.oid AS parent_oid,
    child.relname AS child_table,
    parent.relname AS parent_table,
    ARRAY(
      SELECT a.attname
      FROM unnest(con.conkey) WITH ORDINALITY k(attnum,ord)
      JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=k.attnum
      ORDER BY ord
    ) AS child_cols,
    ARRAY(
      SELECT a.attname
      FROM unnest(con.confkey) WITH ORDINALITY k(attnum,ord)
      JOIN pg_attribute a ON a.attrelid=con.confrelid AND a.attnum=k.attnum
      ORDER BY ord
    ) AS parent_cols
  FROM pg_constraint con
  JOIN pg_class child ON child.oid=con.conrelid
  JOIN pg_namespace nsc ON nsc.oid=child.relnamespace
  JOIN pg_class parent ON parent.oid=con.confrelid
  JOIN pg_namespace nsp ON nsp.oid=parent.relnamespace
  WHERE con.contype='f' AND nsc.nspname='growth' AND nsp.nspname='growth'
), parent_is_tenant AS (
  SELECT c.oid
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_attribute a ON a.attrelid=c.oid
  WHERE n.nspname='growth' AND c.relkind='r'
    AND a.attname='workspace_id' AND NOT a.attisdropped
), violations AS (
  SELECT * FROM fk
  WHERE parent_oid IN (SELECT oid FROM parent_is_tenant)
    AND NOT ('workspace_id'=ANY(child_cols) AND 'workspace_id'=ANY(parent_cols))
)
SELECT CASE WHEN count(*)>0 THEN 'true' ELSE 'false' END AS bad_fk FROM violations;
\gset
\if :bad_fk
  \echo 'FAIL: a tenant-parent FK omits workspace_id'
  SELECT conname,child_table,parent_table,child_cols,parent_cols FROM violations;
  SELECT 1 / 0;
\endif

-- B) Every table carrying workspace_id must have ENABLE+FORCE RLS, except explicit internal-only jobs.
WITH workspace_tables AS (
  SELECT DISTINCT c.oid,c.relname
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_attribute a ON a.attrelid=c.oid
  WHERE n.nspname='growth' AND c.relkind='r'
    AND a.attname='workspace_id' AND NOT a.attisdropped
    AND c.relname NOT IN ('jobs')
), bad AS (
  SELECT w.relname FROM workspace_tables w
  JOIN pg_class c ON c.oid=w.oid
  WHERE NOT c.relrowsecurity OR NOT c.relforcerowsecurity
)
SELECT CASE WHEN count(*)>0 THEN 'true' ELSE 'false' END AS bad_rls FROM bad;
\gset
\if :bad_rls
  \echo 'FAIL: workspace-scoped table lacks ENABLE/FORCE RLS'
  SELECT * FROM bad;
  SELECT 1 / 0;
\endif

-- C) Explicit identity bootstrap RLS must exist.
WITH required(tab,pol) AS (VALUES
 ('users','users_self_select'),
 ('memberships','memberships_self_select'),
 ('workspaces','workspaces_member_select')
), missing AS (
 SELECT * FROM required r
 WHERE NOT EXISTS (
   SELECT 1 FROM pg_policies p WHERE p.schemaname='growth' AND p.tablename=r.tab AND p.policyname=r.pol
 )
)
SELECT CASE WHEN count(*)>0 THEN 'true' ELSE 'false' END AS missing_bootstrap_policy FROM missing;
\gset
\if :missing_bootstrap_policy
  \echo 'FAIL: identity/workspace bootstrap RLS policy missing'
  SELECT * FROM missing;
  SELECT 1 / 0;
\endif

-- D) No legacy fixed pgvector column or pgcrypto dependency.
SELECT CASE WHEN count(*)>0 THEN 'true' ELSE 'false' END AS bad_vector
FROM information_schema.columns WHERE table_schema='growth' AND udt_name='vector';
\gset
\if :bad_vector
  \echo 'FAIL: fixed vector column exists before embedding layout freeze'
  SELECT 1 / 0;
\endif
SELECT CASE WHEN count(*)>0 THEN 'true' ELSE 'false' END AS bad_pgcrypto
FROM pg_extension WHERE extname='pgcrypto';
\gset
\if :bad_pgcrypto
  \echo 'FAIL: pgcrypto unexpectedly required by canonical schema'
  SELECT 1 / 0;
\endif

-- E) Critical indexes/constraints introduced by RC3 must exist.
WITH required_idx(name) AS (VALUES
 ('jobs_tenant_operation_uq'),
 ('jobs_global_operation_uq'),
 ('publication_one_active_per_version_account')
), missing AS (
 SELECT name FROM required_idx r WHERE NOT EXISTS (
   SELECT 1 FROM pg_indexes i WHERE i.schemaname='growth' AND i.indexname=r.name
 )
)
SELECT CASE WHEN count(*)>0 THEN 'true' ELSE 'false' END AS missing_idx FROM missing;
\gset
\if :missing_idx
  \echo 'FAIL: required unique/partial index missing'
  SELECT * FROM missing;
  SELECT 1 / 0;
\endif

\echo 'PASS: dynamic catalog invariants'
