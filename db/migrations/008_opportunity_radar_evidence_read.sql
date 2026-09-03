-- Growth OS — Opportunity Radar evidence read boundary (Issue #21).
--
-- Forward-only least-privilege migration. The first real Opportunity Radar
-- product slice needs app_runtime to read evidence already protected by
-- workspace RLS. No write capability is added and no schema shape changes.
--
-- Execution identity: growth_migrator.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime') THEN
    RAISE EXCEPTION 'Issue #21 evidence-read migration aborted: app_runtime role is missing';
  END IF;

  IF to_regclass('growth.opportunity_evidence') IS NULL
     OR to_regclass('growth.insight_evidence') IS NULL THEN
    RAISE EXCEPTION 'Issue #21 evidence-read migration aborted: required evidence table is missing';
  END IF;

  IF NOT (
    SELECT c.relrowsecurity AND c.relforcerowsecurity
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'growth' AND c.relname = 'opportunity_evidence'
  ) THEN
    RAISE EXCEPTION 'Issue #21 evidence-read migration aborted: opportunity_evidence is not RLS+FORCE protected';
  END IF;

  IF NOT (
    SELECT c.relrowsecurity AND c.relforcerowsecurity
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'growth' AND c.relname = 'insight_evidence'
  ) THEN
    RAISE EXCEPTION 'Issue #21 evidence-read migration aborted: insight_evidence is not RLS+FORCE protected';
  END IF;
END $$;

GRANT SELECT ON growth.opportunity_evidence TO app_runtime;
GRANT SELECT ON growth.insight_evidence TO app_runtime;

COMMIT;
