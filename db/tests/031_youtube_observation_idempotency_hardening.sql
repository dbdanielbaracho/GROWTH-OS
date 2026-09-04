-- Issue #26 regression gate: material observation identity must be conflict-safe.
-- Catalog-only. Behavioral conflict cases are also exercised by the validation-cluster smoke.
\set ON_ERROR_STOP on

DO $$
DECLARE
  fn regprocedure := 'growth.youtube_record_metric_observation(uuid,text,text,numeric,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,timestamp with time zone,text,text,uuid,text,text,text,text)'::regprocedure;
  def text;
  required_fragment text;
BEGIN
  SELECT pg_get_functiondef(fn) INTO def;

  IF def IS NULL OR position('IS NOT DISTINCT FROM' in def)=0 THEN
    RAISE EXCEPTION '031 failed: idempotency comparison must be NULL-safe and explicit';
  END IF;

  FOREACH required_fragment IN ARRAY ARRAY[
    'existing.social_account_id',
    'existing.provider_content_id',
    'existing.metric_name',
    'existing.raw_value',
    'existing.unit',
    'existing.observed_at',
    'existing.provider_effective_at',
    'existing.provider_api_version',
    'existing.source_schema_version',
    'existing.collection_method',
    'existing.raw_payload_ref',
    'existing.adapter_version',
    'existing.provider_product',
    'existing.provider_object_type',
    'existing.metric_semantic_version',
    'existing.semantic_effective_from',
    'existing.semantic_effective_to',
    'existing.source_range_start',
    'existing.source_range_end',
    'existing.authorization_class',
    'existing.completeness_status',
    'existing.freshness_status',
    'existing.collection_run_id'
  ] LOOP
    IF position(required_fragment in def)=0 THEN
      RAISE EXCEPTION '031 failed: material idempotency field missing from comparison: %', required_fragment;
    END IF;
  END LOOP;

  IF has_function_privilege('public',fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '031 failed: PUBLIC can execute youtube_record_metric_observation';
  END IF;

  IF NOT has_function_privilege('app_runtime',fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '031 failed: app_runtime lost required helper EXECUTE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid=fn
      AND pg_get_userbyid(p.proowner)='growth_migrator'
      AND p.prosecdef
  ) THEN
    RAISE EXCEPTION '031 failed: helper ownership/security boundary changed';
  END IF;
END $$;

SELECT 'PASS: Issue #26 YouTube observation idempotency compares all stable factual/source identity fields including unit/completeness/freshness' AS result;
