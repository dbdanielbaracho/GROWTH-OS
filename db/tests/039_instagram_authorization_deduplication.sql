BEGIN;

DO $$
DECLARE
  status_oid oid;
  begin_oid oid;
  status_def text;
  begin_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
BEGIN
  status_oid := to_regprocedure('growth.instagram_integration_status()');
  begin_oid := to_regprocedure('growth.instagram_begin_authorization(uuid,text[])');

  IF status_oid IS NULL OR begin_oid IS NULL THEN
    RAISE EXCEPTION '039 failed: Instagram deduplication helpers are missing';
  END IF;

  SELECT pg_get_functiondef(status_oid) INTO status_def;
  SELECT pg_get_functiondef(begin_oid) INTO begin_def;

  IF position('left join lateral' IN lower(status_def)) = 0
     OR position('when ''connected'' then 0' IN lower(status_def)) = 0
     OR position('limit 1' IN lower(status_def)) = 0
  THEN
    RAISE EXCEPTION '039 failed: status helper does not project one prioritized connection';
  END IF;

  IF position('instagram_authorization_superseded' IN lower(begin_def)) = 0
     OR position('state=''authorizing''' IN lower(begin_def)) = 0
     OR position('state in (''revoked'',' IN lower(begin_def)) = 0
     OR position('if connection_id is null' IN lower(begin_def)) = 0
     OR position('for update' IN lower(begin_def)) = 0
  THEN
    RAISE EXCEPTION '039 failed: authorization helper does not supersede stale authorizations safely';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid=p.proowner
  WHERE p.oid=status_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '039 failed: status helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', status_oid, 'EXECUTE')
    INTO app_execute;
  SELECT has_function_privilege('public', status_oid, 'EXECUTE')
    INTO public_execute;

  IF app_execute IS DISTINCT FROM true OR public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION '039 failed: status helper grants';
  END IF;

  IF has_table_privilege('app_runtime','growth.platform_connections','SELECT')
     OR has_table_privilege('app_runtime','growth.platform_connections','INSERT')
     OR has_table_privilege('app_runtime','growth.platform_connections','UPDATE')
     OR has_table_privilege('app_runtime','growth.platform_connections','DELETE')
  THEN
    RAISE EXCEPTION '039 failed: direct runtime platform connection access widened';
  END IF;
END;
$$;

ROLLBACK;

\echo 'PASS 039_instagram_authorization_deduplication'
