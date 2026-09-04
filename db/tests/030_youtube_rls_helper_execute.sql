-- Issue #26 regression gate: YouTube helper dependency on workspace RLS predicate.
-- Catalog-only: creates no provider/user/product data.
\set ON_ERROR_STOP on

DO $$
DECLARE
  ws_fn regprocedure := 'growth.workspace_row_visible(uuid)'::regprocedure;
  yt_fn regprocedure;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid=ws_fn
      AND pg_get_userbyid(p.proowner)='growth_rls_helper'
      AND p.prosecdef
  ) THEN
    RAISE EXCEPTION '030 failed: workspace_row_visible(uuid) ownership/security boundary changed';
  END IF;

  IF has_function_privilege('public',ws_fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '030 failed: PUBLIC can execute workspace_row_visible(uuid)';
  END IF;

  IF NOT has_function_privilege('app_runtime',ws_fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '030 failed: app_runtime lost workspace_row_visible(uuid) execute';
  END IF;

  IF NOT has_function_privilege('growth_migrator',ws_fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '030 failed: growth_migrator lacks workspace_row_visible(uuid) execute required by YouTube SECURITY DEFINER path';
  END IF;

  FOREACH yt_fn IN ARRAY ARRAY[
    'growth.youtube_begin_authorization(uuid,text[])'::regprocedure,
    'growth.youtube_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamp with time zone,boolean,text[])'::regprocedure,
    'growth.youtube_get_connection_credential(uuid)'::regprocedure,
    'growth.youtube_update_connection_credential(uuid,bytea,text,text,timestamp with time zone,boolean,text[])'::regprocedure,
    'growth.youtube_record_metric_observation(uuid,text,text,numeric,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,timestamp with time zone,text,text,uuid,text,text,text,text)'::regprocedure
  ] LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_proc p
      WHERE p.oid=yt_fn
        AND pg_get_userbyid(p.proowner)='growth_migrator'
        AND p.prosecdef
    ) THEN
      RAISE EXCEPTION '030 failed: YouTube helper % ownership/security boundary changed', yt_fn;
    END IF;
    IF has_function_privilege('public',yt_fn::text,'EXECUTE') THEN
      RAISE EXCEPTION '030 failed: PUBLIC can execute YouTube helper %', yt_fn;
    END IF;
    IF NOT has_function_privilege('app_runtime',yt_fn::text,'EXECUTE') THEN
      RAISE EXCEPTION '030 failed: app_runtime lost YouTube helper execute %', yt_fn;
    END IF;
  END LOOP;

  IF has_table_privilege('app_runtime','growth.provider_credentials','SELECT')
     OR has_table_privilege('app_runtime','growth.provider_credentials','INSERT')
     OR has_table_privilege('app_runtime','growth.provider_credentials','UPDATE')
     OR has_table_privilege('app_runtime','growth.provider_credentials','DELETE')
     OR has_table_privilege('app_runtime','growth.platform_connections','SELECT')
     OR has_table_privilege('app_runtime','growth.platform_connections','INSERT')
     OR has_table_privilege('app_runtime','growth.platform_connections','UPDATE')
     OR has_table_privilege('app_runtime','growth.platform_connections','DELETE')
     OR has_table_privilege('app_runtime','growth.metric_observations','SELECT')
     OR has_table_privilege('app_runtime','growth.metric_observations','INSERT')
     OR has_table_privilege('app_runtime','growth.metric_observations','UPDATE')
     OR has_table_privilege('app_runtime','growth.metric_observations','DELETE') THEN
    RAISE EXCEPTION '030 failed: direct app_runtime table boundary widened';
  END IF;
END $$;

SELECT 'PASS: Issue #26 grants only the required workspace RLS predicate execute to growth_migrator' AS result;
