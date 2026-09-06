BEGIN;

DO $$
DECLARE
  helper_name text;
  expected_args text;
  helper_args text;
  helper_oid oid;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
BEGIN
  FOR helper_name, expected_args IN
    SELECT *
    FROM (VALUES
      ('instagram_begin_authorization', 'uuid,text[]'),
      ('instagram_complete_authorization', 'uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[]'),
      ('instagram_revoke_connection', 'uuid')
    ) AS helpers(name,args)
  LOOP
    SELECT r.rolname, p.prosecdef, pg_get_function_identity_arguments(p.oid), p.oid
      INTO helper_owner, is_definer, helper_args, helper_oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    JOIN pg_roles r ON r.oid=p.proowner
    WHERE n.nspname='growth'
      AND p.proname=helper_name;

    IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
      RAISE EXCEPTION '036 failed: % owner/SECURITY DEFINER boundary', helper_name;
    END IF;
    IF replace(helper_args, ' ', '') <> replace(expected_args, ' ', '') THEN
      RAISE EXCEPTION '036 failed: % signature mismatch', helper_name;
    END IF;

    SELECT has_function_privilege('app_runtime', helper_oid, 'EXECUTE')
      INTO app_execute;
    SELECT has_function_privilege('public', helper_oid, 'EXECUTE')
      INTO public_execute;

    IF app_execute IS DISTINCT FROM true OR public_execute IS DISTINCT FROM false THEN
      RAISE EXCEPTION '036 failed: % grants', helper_name;
    END IF;
  END LOOP;

  IF has_table_privilege('app_runtime','growth.provider_credentials','SELECT')
     OR has_table_privilege('app_runtime','growth.provider_credentials','INSERT')
     OR has_table_privilege('app_runtime','growth.provider_credentials','UPDATE')
     OR has_table_privilege('app_runtime','growth.provider_credentials','DELETE')
  THEN
    RAISE EXCEPTION '036 failed: app_runtime received direct provider credential access';
  END IF;

  IF has_table_privilege('app_runtime','growth.platform_connections','SELECT')
     OR has_table_privilege('app_runtime','growth.platform_connections','INSERT')
     OR has_table_privilege('app_runtime','growth.platform_connections','UPDATE')
     OR has_table_privilege('app_runtime','growth.platform_connections','DELETE')
  THEN
    RAISE EXCEPTION '036 failed: app_runtime received direct platform connection access';
  END IF;
END;
$$;

ROLLBACK;

\echo 'PASS 036_instagram_token_lifecycle'
