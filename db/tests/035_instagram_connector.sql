BEGIN;

DO $$
DECLARE
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
  capability_count integer;
BEGIN
  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  JOIN pg_roles r ON r.oid=p.proowner
  WHERE n.nspname='growth'
    AND p.proname='instagram_integration_status'
    AND pg_get_function_identity_arguments(p.oid)='';

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'instagram status helper owner/SECURITY DEFINER boundary failed';
  END IF;

  SELECT has_function_privilege(
    'app_runtime',
    'growth.instagram_integration_status()',
    'EXECUTE'
  ) INTO app_execute;
  SELECT has_function_privilege(
    'public',
    'growth.instagram_integration_status()',
    'EXECUTE'
  ) INTO public_execute;

  IF app_execute IS DISTINCT FROM true OR public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'instagram status helper grants failed';
  END IF;

  SELECT count(*) INTO capability_count
  FROM growth.capabilities
  WHERE platform='instagram'
    AND capability IN ('authorized_profile','content_publish','authorized_insights');

  IF capability_count <> 3 THEN
    RAISE EXCEPTION 'instagram capability registry incomplete';
  END IF;
END;
$$;

ROLLBACK;

\echo 'PASS 035_instagram_connector'
