BEGIN;

DO $$
DECLARE
  rel_rls boolean;
  rel_force boolean;
  app_select boolean;
  app_insert boolean;
  app_update boolean;
  app_delete boolean;
  helper_name text;
  helper_args text;
  helper_oid oid;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
BEGIN
  SELECT c.relrowsecurity, c.relforcerowsecurity
    INTO rel_rls, rel_force
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='growth' AND c.relname='instagram_media';

  IF rel_rls IS DISTINCT FROM true OR rel_force IS DISTINCT FROM true THEN
    RAISE EXCEPTION '037 failed: instagram_media RLS/FORCE RLS boundary';
  END IF;

  SELECT has_table_privilege('app_runtime','growth.instagram_media','SELECT'),
         has_table_privilege('app_runtime','growth.instagram_media','INSERT'),
         has_table_privilege('app_runtime','growth.instagram_media','UPDATE'),
         has_table_privilege('app_runtime','growth.instagram_media','DELETE')
    INTO app_select, app_insert, app_update, app_delete;

  IF app_select OR app_insert OR app_update OR app_delete THEN
    RAISE EXCEPTION '037 failed: app_runtime received direct instagram_media access';
  END IF;

  FOR helper_name, helper_args IN
    SELECT *
    FROM (VALUES
      ('instagram_record_media', 'uuid,text,text,text,text,text,timestamptz,text,text,timestamptz,text,text'),
      ('instagram_record_metric_observation', 'uuid,text,text,numeric,text,timestamptz,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,text,timestamptz,timestamptz,text,text,uuid,text,text,text,text')
    ) AS helpers(name,args)
  LOOP
    helper_oid := to_regprocedure(format('growth.%s(%s)', helper_name, helper_args));
    SELECT r.rolname, p.prosecdef
      INTO helper_owner, is_definer
    FROM pg_proc p
    JOIN pg_roles r ON r.oid=p.proowner
    WHERE p.oid=helper_oid;

    IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
      RAISE EXCEPTION '037 failed: % owner/SECURITY DEFINER boundary', helper_name;
    END IF;

    SELECT has_function_privilege('app_runtime', helper_oid, 'EXECUTE'),
           has_function_privilege('public', helper_oid, 'EXECUTE')
      INTO app_execute, public_execute;

    IF app_execute IS DISTINCT FROM true OR public_execute IS DISTINCT FROM false THEN
      RAISE EXCEPTION '037 failed: % grants', helper_name;
    END IF;
  END LOOP;
END;
$$;

ROLLBACK;

\echo 'PASS 037_instagram_media_metrics_sync'
