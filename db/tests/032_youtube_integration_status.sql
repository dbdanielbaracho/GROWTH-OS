-- Issue #26 regression gate: authenticated YouTube integration status is narrow.
-- Catalog-only: no provider/user/product data is created.
\set ON_ERROR_STOP on

DO $$
DECLARE
  fn regprocedure := 'growth.youtube_integration_status()'::regprocedure;
  def text;
  normalized_def text;
BEGIN
  SELECT pg_get_functiondef(fn) INTO def;
  normalized_def := regexp_replace(def, '[[:space:]]+', '', 'g');

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid=fn
      AND p.prosecdef
      AND pg_get_userbyid(p.proowner)='growth_migrator'
  ) THEN
    RAISE EXCEPTION '032 failed: status helper must remain SECURITY DEFINER owned by growth_migrator';
  END IF;

  IF has_function_privilege('public',fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '032 failed: PUBLIC can execute youtube_integration_status';
  END IF;

  IF NOT has_function_privilege('app_runtime',fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '032 failed: app_runtime lacks youtube_integration_status EXECUTE';
  END IF;

  IF has_table_privilege('app_runtime','growth.managed_accounts','SELECT')
     OR has_table_privilege('app_runtime','growth.platform_connections','SELECT') THEN
    RAISE EXCEPTION '032 failed: direct app_runtime read boundary widened';
  END IF;

  IF def IS NULL
     OR position('growth.current_workspace_id()' in normalized_def)=0
     OR position('growth.tenant_context_valid(ma.workspace_id)' in normalized_def)=0
     OR position('ma.authority_status=''contractually_granted''' in normalized_def)=0
     OR position('p.platform=''youtube''' in normalized_def)=0 THEN
    RAISE EXCEPTION '032 failed: helper lost tenant/authority/provider filters after whitespace-normalized inspection';
  END IF;

  IF position('credential_ciphertext' in def)>0
     OR position('provider_credentials' in def)>0 THEN
    RAISE EXCEPTION '032 failed: status helper references provider credential secret material';
  END IF;
END $$;

SELECT 'PASS: Issue #26 YouTube integration status is tenant-safe, authority-scoped and non-secret' AS result;
