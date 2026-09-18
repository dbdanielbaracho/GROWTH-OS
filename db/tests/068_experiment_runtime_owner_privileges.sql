-- Growth OS — experiment runtime helper execution regression gate.
-- Reproduces the production path through app_runtime while keeping direct
-- writes behind the reviewed SECURITY DEFINER helpers.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT has_table_privilege('growth_migrator', 'growth.opportunities', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.opportunity_evidence', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.hypotheses', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.hypotheses', 'INSERT')
     OR NOT has_table_privilege('growth_migrator', 'growth.experiments', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.experiments', 'INSERT')
     OR NOT has_table_privilege('growth_migrator', 'growth.experiments', 'UPDATE')
  THEN
    RAISE EXCEPTION '068 failed: experiment helper owner privileges are incomplete';
  END IF;

  IF has_table_privilege('app_runtime', 'growth.hypotheses', 'INSERT')
     OR has_table_privilege('app_runtime', 'growth.experiments', 'INSERT')
     OR has_table_privilege('app_runtime', 'growth.experiments', 'UPDATE')
  THEN
    RAISE EXCEPTION '068 failed: app_runtime received direct experiment writes';
  END IF;
END $$;

INSERT INTO growth.opportunities (
  id,
  workspace_id,
  market,
  platform,
  status,
  score,
  confidence,
  ranking_version,
  expires_at
) VALUES (
  'e6800000-0000-4000-8000-000000000001',
  'b0000000-0000-4000-8000-000000000001',
  'US',
  'instagram',
  'active',
  75,
  '{"label":"medium"}'::jsonb,
  'experiment-runtime-privilege-test-v1',
  now() + interval '1 day'
);

INSERT INTO growth.opportunity_evidence (
  id,
  workspace_id,
  opportunity_id,
  source_class,
  evidence_ref,
  observed_at
) VALUES (
  'e6800000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000001',
  'e6800000-0000-4000-8000-000000000001',
  'metric_observation',
  'metric_observation:experiment-runtime-privilege-test-v1',
  now()
);

SELECT set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', false);
SELECT set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', false);

SET ROLE app_runtime;

SELECT count(*) >= 0 AS experiment_list_executes
FROM growth.list_experiments(
  'b0000000-0000-4000-8000-000000000001',
  100
);

SELECT id AS created_experiment_id
FROM growth.create_experiment(
  'b0000000-0000-4000-8000-000000000001',
  'e6800000-0000-4000-8000-000000000001',
  'Runtime privilege experiment',
  'A stored evidence signal can support one controlled experiment.',
  'Record a winner only with an evidence reference.'
) \gset

SELECT id AS created_variant_id
FROM growth.add_experiment_variant(
  'b0000000-0000-4000-8000-000000000001',
  :'created_experiment_id'::uuid,
  'Evidence-backed variant',
  jsonb_build_object(
    'source_opportunity_id',
    'e6800000-0000-4000-8000-000000000001'
  )
) \gset

SELECT count(*) = 1 AS experiment_variant_list_executes
FROM growth.list_experiment_variants(
  'b0000000-0000-4000-8000-000000000001',
  :'created_experiment_id'::uuid
);

SELECT count(*) = 1 AS experiment_feedback_executes
FROM growth.record_experiment_feedback(
  'b0000000-0000-4000-8000-000000000001',
  :'created_experiment_id'::uuid,
  :'created_variant_id'::uuid,
  'winner',
  'metric_observation:experiment-runtime-privilege-test-v1',
  'Runtime privilege regression proof.'
);

RESET ROLE;

ROLLBACK;

SELECT 'TEST-068 PASS: app_runtime experiment helpers execute through least privilege' AS result;
