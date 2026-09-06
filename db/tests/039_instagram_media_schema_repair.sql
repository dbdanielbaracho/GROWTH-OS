\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  media_fn regprocedure := 'growth.instagram_record_media(uuid,text,text,text,text,text,timestamp with time zone,text,text,timestamp with time zone,text,text)'::regprocedure;
  observation_fn regprocedure := 'growth.instagram_record_metric_observation(uuid,text,text,numeric,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,timestamp with time zone,text,text,uuid,text,text,text,text)'::regprocedure;
  rel record;
BEGIN
  SELECT c.relrowsecurity, c.relforcerowsecurity
    INTO rel
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='growth' AND c.relname='instagram_media';

  IF NOT FOUND OR NOT rel.relrowsecurity OR NOT rel.relforcerowsecurity THEN
    RAISE EXCEPTION '039 failed: instagram_media must have RLS and FORCE RLS';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='growth'
      AND tablename='instagram_media'
      AND policyname='instagram_media_workspace_isolation'
      AND qual LIKE '%current_workspace_id%'
      AND qual LIKE '%tenant_context_valid%'
      AND with_check LIKE '%current_workspace_id%'
      AND with_check LIKE '%tenant_context_valid%'
  ) THEN
    RAISE EXCEPTION '039 failed: Instagram media tenant policy missing or incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid=media_fn
      AND pg_get_userbyid(p.proowner)='growth_migrator'
      AND p.prosecdef
  ) THEN
    RAISE EXCEPTION '039 failed: Instagram media helper security boundary changed';
  END IF;

  IF has_function_privilege('public',media_fn,'EXECUTE')
     OR NOT has_function_privilege('app_runtime',media_fn,'EXECUTE') THEN
    RAISE EXCEPTION '039 failed: Instagram media helper grants changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid=observation_fn
      AND pg_get_userbyid(p.proowner)='growth_migrator'
      AND p.prosecdef
      AND p.prosrc LIKE '%ROW(%'
  ) THEN
    RAISE EXCEPTION '039 failed: hardened Instagram observation helper missing';
  END IF;

  IF has_function_privilege('public',observation_fn,'EXECUTE')
     OR NOT has_function_privilege('app_runtime',observation_fn,'EXECUTE') THEN
    RAISE EXCEPTION '039 failed: Instagram observation helper grants changed';
  END IF;

  IF has_table_privilege('app_runtime','growth.instagram_media','SELECT')
     OR has_table_privilege('app_runtime','growth.instagram_media','INSERT')
     OR has_table_privilege('app_runtime','growth.instagram_media','UPDATE')
     OR has_table_privilege('app_runtime','growth.instagram_media','DELETE') THEN
    RAISE EXCEPTION '039 failed: app_runtime has direct Instagram media table access';
  END IF;

  IF EXISTS (SELECT 1 FROM growth.instagram_media) THEN
    RAISE EXCEPTION '039 failed: isolated schema unexpectedly contains Instagram media rows';
  END IF;
END
$$;

ROLLBACK;

SELECT '039 Instagram media schema repair gate: PASS' AS result;
