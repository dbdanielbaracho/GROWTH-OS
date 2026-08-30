\set ON_ERROR_STOP on
SET search_path = growth, public;

-- Static catalog assertions for RC3-specific correctness.
DO $$
DECLARE n int;
BEGIN
  -- metric_normalized lifetime/window-null duplicates must be blocked by NULLS NOT DISTINCT unique index/constraint.
  SELECT count(*) INTO n
  FROM pg_index i
  JOIN pg_class c ON c.oid=i.indrelid
  JOIN pg_namespace ns ON ns.oid=c.relnamespace
  WHERE ns.nspname='growth' AND c.relname='metric_normalized'
    AND i.indisunique AND i.indnullsnotdistinct;
  IF n=0 THEN RAISE EXCEPTION 'RC3 FAIL: metric_normalized lacks NULLS NOT DISTINCT uniqueness'; END IF;

  -- jobs intentionally has no RLS; it must have split tenant/global uniqueness indexes.
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='growth' AND indexname='jobs_tenant_operation_uq')
     OR NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='growth' AND indexname='jobs_global_operation_uq') THEN
    RAISE EXCEPTION 'RC3 FAIL: jobs split uniqueness indexes missing';
  END IF;
END $$;

\echo 'PASS: RC3 integrity catalog assertions'
