-- Issue #17 regression gate: PUBLIC EXECUTE least privilege.
-- Run after migration 007 on the isolated validation cluster.
\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  public_execute_count integer;
  wrong_owner_count integer;
  app_runtime_unexpected integer;
  rls_helper_unexpected integer;
  identity_helper_unexpected integer;
BEGIN
  WITH expected(identity) AS (
    VALUES
      ('growth.assert_confirmed_insight_evidence_purity(uuid,uuid)'::text),
      ('growth.check_authority_history_projection_consistency()'),
      ('growth.check_insight_evidence_purity()'),
      ('growth.check_insight_state_evidence_purity()'),
      ('growth.check_managed_account_projection_consistency()'),
      ('growth.content_approval_assign_decision_no()'),
      ('growth.content_version_visible(uuid,uuid)'),
      ('growth.current_app_user_id()'),
      ('growth.current_workspace_id()'),
      ('growth.enforce_deletion_request_state_transition()'),
      ('growth.enforce_experiment_outcome_temporal_integrity()'),
      ('growth.enforce_experiment_temporal_integrity()'),
      ('growth.enforce_exposure_temporal_integrity()'),
      ('growth.invalidate_metric_completeness_on_late_observation()'),
      ('growth.reject_insight_demotion_cycle()'),
      ('growth.reject_mutation_while_retained()')
  ), funcs AS (
    SELECT p.*
    FROM expected e
    JOIN pg_proc p ON p.oid = to_regprocedure(e.identity)
  ), public_acl AS (
    SELECT f.oid
    FROM funcs f
    CROSS JOIN LATERAL aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) x
    WHERE x.grantee = 0 AND x.privilege_type = 'EXECUTE'
  )
  SELECT count(*) INTO public_execute_count FROM public_acl;

  IF public_execute_count <> 0 THEN
    RAISE EXCEPTION '026 failed: % reviewed functions still grant EXECUTE to PUBLIC', public_execute_count;
  END IF;

  WITH expected(identity) AS (
    VALUES
      ('growth.assert_confirmed_insight_evidence_purity(uuid,uuid)'::text),
      ('growth.check_authority_history_projection_consistency()'),
      ('growth.check_insight_evidence_purity()'),
      ('growth.check_insight_state_evidence_purity()'),
      ('growth.check_managed_account_projection_consistency()'),
      ('growth.content_approval_assign_decision_no()'),
      ('growth.content_version_visible(uuid,uuid)'),
      ('growth.current_app_user_id()'),
      ('growth.current_workspace_id()'),
      ('growth.enforce_deletion_request_state_transition()'),
      ('growth.enforce_experiment_outcome_temporal_integrity()'),
      ('growth.enforce_experiment_temporal_integrity()'),
      ('growth.enforce_exposure_temporal_integrity()'),
      ('growth.invalidate_metric_completeness_on_late_observation()'),
      ('growth.reject_insight_demotion_cycle()'),
      ('growth.reject_mutation_while_retained()')
  )
  SELECT count(*) INTO wrong_owner_count
  FROM expected e
  JOIN pg_proc p ON p.oid = to_regprocedure(e.identity)
  WHERE pg_get_userbyid(p.proowner) <> 'growth_migrator';

  IF wrong_owner_count <> 0 THEN
    RAISE EXCEPTION '026 failed: reviewed function ownership changed';
  END IF;

  -- app_runtime must have exactly four reviewed capabilities.
  WITH expected(identity, should_execute) AS (
    VALUES
      ('growth.assert_confirmed_insight_evidence_purity(uuid,uuid)'::text, true),
      ('growth.check_authority_history_projection_consistency()', false),
      ('growth.check_insight_evidence_purity()', false),
      ('growth.check_insight_state_evidence_purity()', false),
      ('growth.check_managed_account_projection_consistency()', false),
      ('growth.content_approval_assign_decision_no()', false),
      ('growth.content_version_visible(uuid,uuid)', true),
      ('growth.current_app_user_id()', true),
      ('growth.current_workspace_id()', true),
      ('growth.enforce_deletion_request_state_transition()', false),
      ('growth.enforce_experiment_outcome_temporal_integrity()', false),
      ('growth.enforce_experiment_temporal_integrity()', false),
      ('growth.enforce_exposure_temporal_integrity()', false),
      ('growth.invalidate_metric_completeness_on_late_observation()', false),
      ('growth.reject_insight_demotion_cycle()', false),
      ('growth.reject_mutation_while_retained()', false)
  )
  SELECT count(*) INTO app_runtime_unexpected
  FROM expected
  WHERE has_function_privilege('app_runtime', identity, 'EXECUTE') IS DISTINCT FROM should_execute;

  IF app_runtime_unexpected <> 0 THEN
    RAISE EXCEPTION '026 failed: app_runtime EXECUTE matrix differs in % reviewed functions', app_runtime_unexpected;
  END IF;

  -- growth_rls_helper gets only the two context helpers among the reviewed set.
  WITH expected(identity, should_execute) AS (
    VALUES
      ('growth.assert_confirmed_insight_evidence_purity(uuid,uuid)'::text, false),
      ('growth.check_authority_history_projection_consistency()', false),
      ('growth.check_insight_evidence_purity()', false),
      ('growth.check_insight_state_evidence_purity()', false),
      ('growth.check_managed_account_projection_consistency()', false),
      ('growth.content_approval_assign_decision_no()', false),
      ('growth.content_version_visible(uuid,uuid)', false),
      ('growth.current_app_user_id()', true),
      ('growth.current_workspace_id()', true),
      ('growth.enforce_deletion_request_state_transition()', false),
      ('growth.enforce_experiment_outcome_temporal_integrity()', false),
      ('growth.enforce_experiment_temporal_integrity()', false),
      ('growth.enforce_exposure_temporal_integrity()', false),
      ('growth.invalidate_metric_completeness_on_late_observation()', false),
      ('growth.reject_insight_demotion_cycle()', false),
      ('growth.reject_mutation_while_retained()', false)
  )
  SELECT count(*) INTO rls_helper_unexpected
  FROM expected
  WHERE has_function_privilege('growth_rls_helper', identity, 'EXECUTE') IS DISTINCT FROM should_execute;

  IF rls_helper_unexpected <> 0 THEN
    RAISE EXCEPTION '026 failed: growth_rls_helper EXECUTE matrix differs in % reviewed functions', rls_helper_unexpected;
  END IF;

  -- growth_identity_helper gets only the two context helpers among the reviewed set.
  WITH expected(identity, should_execute) AS (
    VALUES
      ('growth.assert_confirmed_insight_evidence_purity(uuid,uuid)'::text, false),
      ('growth.check_authority_history_projection_consistency()', false),
      ('growth.check_insight_evidence_purity()', false),
      ('growth.check_insight_state_evidence_purity()', false),
      ('growth.check_managed_account_projection_consistency()', false),
      ('growth.content_approval_assign_decision_no()', false),
      ('growth.content_version_visible(uuid,uuid)', false),
      ('growth.current_app_user_id()', true),
      ('growth.current_workspace_id()', true),
      ('growth.enforce_deletion_request_state_transition()', false),
      ('growth.enforce_experiment_outcome_temporal_integrity()', false),
      ('growth.enforce_experiment_temporal_integrity()', false),
      ('growth.enforce_exposure_temporal_integrity()', false),
      ('growth.invalidate_metric_completeness_on_late_observation()', false),
      ('growth.reject_insight_demotion_cycle()', false),
      ('growth.reject_mutation_while_retained()', false)
  )
  SELECT count(*) INTO identity_helper_unexpected
  FROM expected
  WHERE has_function_privilege('growth_identity_helper', identity, 'EXECUTE') IS DISTINCT FROM should_execute;

  IF identity_helper_unexpected <> 0 THEN
    RAISE EXCEPTION '026 failed: growth_identity_helper EXECUTE matrix differs in % reviewed functions', identity_helper_unexpected;
  END IF;
END $$;

-- Real direct-call smoke for the three runtime helpers. These must fail only by
-- business/RLS semantics, never by function privilege.
SET ROLE app_runtime;
SELECT growth.current_app_user_id();
SELECT growth.current_workspace_id();
SELECT growth.content_version_visible(gen_random_uuid(), gen_random_uuid());
RESET ROLE;

\echo 'PASS 026_public_execute_least_privilege'
