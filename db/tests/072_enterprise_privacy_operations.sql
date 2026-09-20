-- Enterprise, support and privacy operations contract gate.
\set ON_ERROR_STOP on

DO $enterprise_privacy_gate$
DECLARE
  signature text;
  oid_value oid;
  definition text;
  owner_name text;
  is_definer boolean;
  table_name text;
BEGIN
  FOREACH signature IN ARRAY ARRAY[
    'growth.list_agency_clients(uuid)',
    'growth.set_agency_client(uuid,uuid,text,text)',
    'growth.list_support_cases(uuid,integer)',
    'growth.create_support_case(uuid,text,text,text,text)',
    'growth.update_support_case(uuid,uuid,text,text)',
    'growth.list_latest_consents(uuid)',
    'growth.record_workspace_consent(uuid,uuid,text,text,text)',
    'growth.list_deletion_requests(uuid,integer)',
    'growth.create_deletion_request(uuid,text,uuid,text)',
    'growth.tombstone_deletion_request(uuid,uuid)'
  ] LOOP
    oid_value := to_regprocedure(signature);
    IF oid_value IS NULL THEN
      RAISE EXCEPTION '072 failed: helper % is missing', signature;
    END IF;
    SELECT r.rolname, p.prosecdef, pg_get_functiondef(p.oid)
      INTO owner_name, is_definer, definition
      FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
     WHERE p.oid = oid_value;
    IF owner_name <> 'growth_migrator' OR is_definer IS DISTINCT FROM true
       OR has_function_privilege('app_runtime', oid_value, 'EXECUTE') IS DISTINCT FROM true
       OR has_function_privilege('public', oid_value, 'EXECUTE') IS DISTINCT FROM false THEN
      RAISE EXCEPTION '072 failed: helper % privilege boundary', signature;
    END IF;
  END LOOP;

  FOREACH table_name IN ARRAY ARRAY[
    'agency_client_links','support_cases','support_case_events'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c
       WHERE c.oid = format('growth.%I', table_name)::regclass
         AND c.relrowsecurity AND c.relforcerowsecurity
    ) OR has_table_privilege('app_runtime', format('growth.%I', table_name), 'SELECT') THEN
      RAISE EXCEPTION '072 failed: table % privilege/RLS boundary', table_name;
    END IF;
  END LOOP;

  SELECT string_agg(pg_get_functiondef(p.oid), E'\n') INTO definition
    FROM pg_proc p
   WHERE p.oid IN (
     to_regprocedure('growth.set_agency_client(uuid,uuid,text,text)'),
     to_regprocedure('growth.record_workspace_consent(uuid,uuid,text,text,text)'),
     to_regprocedure('growth.create_deletion_request(uuid,text,uuid,text)'),
     to_regprocedure('growth.tombstone_deletion_request(uuid,uuid)')
   );
  IF position('administration rights in both workspaces' IN lower(definition)) = 0
     OR position('consent management requires owner or admin' IN lower(definition)) = 0
     OR position('deletion request requires owner or admin' IN lower(definition)) = 0
     OR position('deletion_tombstones' IN lower(definition)) = 0
     OR position('deletion target is already tombstoned' IN lower(definition)) = 0
     OR position('privacy.deletion.tombstoned' IN lower(definition)) = 0 THEN
    RAISE EXCEPTION '072 failed: enterprise/privacy controls are incomplete';
  END IF;
END;
$enterprise_privacy_gate$;

SELECT 'TEST-072 PASS: enterprise, support and privacy operations' AS result;
