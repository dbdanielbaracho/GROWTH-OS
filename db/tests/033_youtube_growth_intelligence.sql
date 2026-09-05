-- SQL gate 033: deterministic YouTube Growth Intelligence Engine.
-- This gate verifies the database contract; execution against real observations
-- belongs to the isolated integration validator.

DO $$
DECLARE
  signal_fn regprocedure := 'growth.recompute_youtube_growth_intelligence(uuid)'::regprocedure;
BEGIN
  IF to_regclass('growth.factual_signals') IS NULL THEN
    RAISE EXCEPTION '033 failed: factual_signals table is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'growth'
       AND c.relname = 'insights'
       AND a.attname = 'source_signal_id'
       AND NOT a.attisdropped
  ) THEN
    RAISE EXCEPTION '033 failed: insights.source_signal_id is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'growth'
       AND c.relname = 'opportunities'
       AND a.attname = 'source_signal_id'
       AND NOT a.attisdropped
  ) THEN
    RAISE EXCEPTION '033 failed: opportunities.source_signal_id is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'growth'
       AND c.relname = 'factual_signals'
       AND c.relrowsecurity
       AND c.relforcerowsecurity
  ) THEN
    RAISE EXCEPTION '033 failed: factual_signals must use RLS + FORCE RLS';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM pg_proc p
      WHERE p.oid = signal_fn
        AND p.prosecdef
        AND pg_get_userbyid(p.proowner) = 'growth_migrator'
  ) THEN
    RAISE EXCEPTION '033 failed: recompute helper must be SECURITY DEFINER owned by growth_migrator';
  END IF;

  IF has_function_privilege('public', signal_fn::text, 'EXECUTE') THEN
    RAISE EXCEPTION '033 failed: PUBLIC unexpectedly has EXECUTE on recompute helper';
  END IF;

  IF NOT has_function_privilege('app_runtime', signal_fn::text, 'EXECUTE') THEN
    RAISE EXCEPTION '033 failed: app_runtime lacks recompute helper EXECUTE';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.factual_signals', 'INSERT') THEN
    RAISE EXCEPTION '033 failed: app_runtime must not insert factual_signals directly';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.insights', 'INSERT')
     OR has_table_privilege('app_runtime', 'growth.opportunities', 'INSERT') THEN
    RAISE EXCEPTION '033 failed: app_runtime must not insert insights/opportunities directly';
  END IF;

  IF NOT (pg_get_functiondef(signal_fn) LIKE '%authorization_class = ''authorized_account''%'
          AND pg_get_functiondef(signal_fn) LIKE '%completeness_status = ''complete''%'
          AND pg_get_functiondef(signal_fn) LIKE '%freshness_status = ''fresh''%'
          AND pg_get_functiondef(signal_fn) LIKE '%authority_status = ''contractually_granted''%'
          AND pg_get_functiondef(signal_fn) LIKE '%signal_type%') THEN
    RAISE EXCEPTION '033 failed: recompute helper lacks provenance/authority filters';
  END IF;
END $$;

\echo 'PASS 033_youtube_growth_intelligence'
