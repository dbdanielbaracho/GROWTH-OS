-- Issue #21 regression gate: Opportunity Radar evidence read boundary.
-- Run after migration 008 on the isolated validation cluster.
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT has_table_privilege('app_runtime', 'growth.opportunity_evidence', 'SELECT') THEN
    RAISE EXCEPTION '027 failed: app_runtime lacks SELECT on opportunity_evidence';
  END IF;

  IF NOT has_table_privilege('app_runtime', 'growth.insight_evidence', 'SELECT') THEN
    RAISE EXCEPTION '027 failed: app_runtime lacks SELECT on insight_evidence';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.opportunity_evidence', 'INSERT')
     OR has_table_privilege('app_runtime', 'growth.opportunity_evidence', 'UPDATE')
     OR has_table_privilege('app_runtime', 'growth.opportunity_evidence', 'DELETE') THEN
    RAISE EXCEPTION '027 failed: app_runtime received write privilege on opportunity_evidence';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.insight_evidence', 'INSERT')
     OR has_table_privilege('app_runtime', 'growth.insight_evidence', 'UPDATE')
     OR has_table_privilege('app_runtime', 'growth.insight_evidence', 'DELETE') THEN
    RAISE EXCEPTION '027 failed: app_runtime received write privilege on insight_evidence';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.feed_cards', 'SELECT') THEN
    RAISE EXCEPTION '027 failed: Issue #21 widened runtime access to feed_cards unexpectedly';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'growth'
      AND c.relname IN ('opportunity_evidence','insight_evidence')
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
  ) THEN
    RAISE EXCEPTION '027 failed: evidence table lost RLS or FORCE RLS';
  END IF;
END $$;

SELECT 'PASS: Issue #21 Opportunity Radar evidence read is SELECT-only and RLS+FORCE protected' AS result;
