-- Catalog-only gate for evidence-bounded intelligence modules.
\set ON_ERROR_STOP on

DO $$
DECLARE
  module_rows integer;
BEGIN
  SELECT count(*) INTO module_rows
    FROM growth.capabilities
   WHERE capability IN (
     'intelligence_global_trend_migration',
     'intelligence_competitor_intelligence',
     'intelligence_viral_dna'
   );
  IF module_rows <> 9 THEN
    RAISE EXCEPTION 'expected 9 intelligence module capability rows, found %', module_rows;
  END IF;
  IF EXISTS (
    SELECT 1 FROM growth.capabilities
     WHERE capability LIKE 'intelligence_%'
       AND (evidence_ref IS NULL OR btrim(evidence_ref) = '')
  ) THEN
    RAISE EXCEPTION 'intelligence module capability is missing evidence_ref';
  END IF;
  IF to_regprocedure('growth.list_intelligence_module_capabilities(uuid)') IS NULL
     OR to_regprocedure('growth.list_competitor_intelligence_evidence(uuid,integer)') IS NULL
     OR to_regprocedure('growth.list_viral_dna_evidence(uuid,integer)') IS NULL THEN
    RAISE EXCEPTION 'intelligence module helper is missing';
  END IF;
  IF has_function_privilege('public','growth.list_intelligence_module_capabilities(uuid)','EXECUTE')
     OR has_function_privilege('public','growth.list_competitor_intelligence_evidence(uuid,integer)','EXECUTE')
     OR has_function_privilege('public','growth.list_viral_dna_evidence(uuid,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'public must not execute intelligence module helpers';
  END IF;
  IF NOT has_function_privilege('app_runtime','growth.list_intelligence_module_capabilities(uuid)','EXECUTE')
     OR NOT has_function_privilege('app_runtime','growth.list_competitor_intelligence_evidence(uuid,integer)','EXECUTE')
     OR NOT has_function_privilege('app_runtime','growth.list_viral_dna_evidence(uuid,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'app_runtime is missing intelligence helper execute privilege';
  END IF;
END $$;
