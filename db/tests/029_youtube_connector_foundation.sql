-- Issue #26 regression gate: YouTube connector foundation + active-context hardening.
-- Catalog-only: no provider/user/product data is created.
\set ON_ERROR_STOP on

DO $$
DECLARE
  fn regprocedure;
  required_column text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='growth' AND c.relname='provider_credentials'
      AND c.relrowsecurity AND c.relforcerowsecurity
  ) THEN
    RAISE EXCEPTION '029 failed: provider_credentials must exist with RLS+FORCE';
  END IF;

  IF has_table_privilege('app_runtime','growth.provider_credentials','SELECT')
     OR has_table_privilege('app_runtime','growth.provider_credentials','INSERT')
     OR has_table_privilege('app_runtime','growth.provider_credentials','UPDATE')
     OR has_table_privilege('app_runtime','growth.provider_credentials','DELETE') THEN
    RAISE EXCEPTION '029 failed: app_runtime received direct provider_credentials table privileges';
  END IF;

  IF has_table_privilege('app_runtime','growth.platform_connections','SELECT')
     OR has_table_privilege('app_runtime','growth.platform_connections','INSERT')
     OR has_table_privilege('app_runtime','growth.platform_connections','UPDATE')
     OR has_table_privilege('app_runtime','growth.platform_connections','DELETE') THEN
    RAISE EXCEPTION '029 failed: app_runtime platform_connections boundary widened';
  END IF;

  IF has_table_privilege('app_runtime','growth.metric_observations','SELECT')
     OR has_table_privilege('app_runtime','growth.metric_observations','INSERT')
     OR has_table_privilege('app_runtime','growth.metric_observations','UPDATE')
     OR has_table_privilege('app_runtime','growth.metric_observations','DELETE') THEN
    RAISE EXCEPTION '029 failed: app_runtime metric_observations boundary widened';
  END IF;

  FOREACH required_column IN ARRAY ARRAY[
    'provider_product','provider_object_type','metric_semantic_version',
    'semantic_effective_from','semantic_effective_to','source_range_start','source_range_end',
    'collected_at','authorization_class','retention_deadline','refresh_required_by',
    'completeness_status','freshness_status','collection_run_id','idempotency_key'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='growth' AND table_name='metric_observations'
        AND column_name=required_column
    ) THEN
      RAISE EXCEPTION '029 failed: metric_observations missing column %', required_column;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='growth' AND tablename='metric_observations'
      AND indexname='metric_observations_idempotency_uq'
      AND indexdef ILIKE '%UNIQUE%'
  ) THEN
    RAISE EXCEPTION '029 failed: metric_observations idempotency unique index missing';
  END IF;

  FOREACH fn IN ARRAY ARRAY[
    'growth.youtube_begin_authorization(uuid,text[])'::regprocedure,
    'growth.youtube_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamp with time zone,boolean,text[])'::regprocedure,
    'growth.youtube_get_connection_credential(uuid)'::regprocedure,
    'growth.youtube_update_connection_credential(uuid,bytea,text,text,timestamp with time zone,boolean,text[])'::regprocedure,
    'growth.youtube_record_metric_observation(uuid,text,text,numeric,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,timestamp with time zone,text,text,uuid,text,text,text,text)'::regprocedure
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p
      WHERE p.oid=fn
        AND pg_get_userbyid(p.proowner)='growth_migrator'
        AND p.prosecdef
    ) THEN
      RAISE EXCEPTION '029 failed: % must be SECURITY DEFINER owned by growth_migrator', fn;
    END IF;
    IF has_function_privilege('public',fn::text,'EXECUTE') THEN
      RAISE EXCEPTION '029 failed: PUBLIC retains EXECUTE on %', fn;
    END IF;
    IF NOT has_function_privilege('app_runtime',fn::text,'EXECUTE') THEN
      RAISE EXCEPTION '029 failed: app_runtime lacks EXECUTE on %', fn;
    END IF;
  END LOOP;

  fn := 'growth.provider_credential_active_context_guard()'::regprocedure;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid=fn
      AND pg_get_userbyid(p.proowner)='growth_migrator'
      AND p.prosecdef
  ) THEN
    RAISE EXCEPTION '029 failed: provider credential context guard must be SECURITY DEFINER owned by growth_migrator';
  END IF;
  IF has_function_privilege('public',fn::text,'EXECUTE')
     OR has_function_privilege('app_runtime',fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '029 failed: provider credential context guard must not be directly executable by PUBLIC/app_runtime';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid=t.tgrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='growth'
      AND c.relname='provider_credentials'
      AND t.tgname='provider_credentials_active_context'
      AND NOT t.tgisinternal
      AND pg_get_triggerdef(t.oid) ILIKE '%BEFORE INSERT OR UPDATE%'
  ) THEN
    RAISE EXCEPTION '029 failed: provider credential active-context trigger missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM growth.capabilities
    WHERE platform='youtube' AND market='GLOBAL' AND account_type='channel'
      AND capability='derived_analytics' AND status='disabled' AND kill_switch
      AND coalesce((limits->>'requires_policy_acceptance')::boolean,false)
  ) THEN
    RAISE EXCEPTION '029 failed: YouTube derived_analytics must be fail-closed';
  END IF;

  IF (
    SELECT count(*) FROM growth.capabilities
    WHERE platform='youtube' AND market='GLOBAL' AND account_type='channel'
      AND capability IN ('authorized_analytics','public_metadata','public_stats','push_upload_events','derived_analytics')
  ) <> 5 THEN
    RAISE EXCEPTION '029 failed: expected five Gate Zero YouTube capabilities';
  END IF;
END $$;

SELECT 'PASS: Issue #26 YouTube DB foundation is narrow, provenance-aware, context-hardened and derived analytics is fail-closed' AS result;
