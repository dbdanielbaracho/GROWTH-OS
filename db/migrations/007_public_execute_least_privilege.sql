-- Growth OS — PUBLIC EXECUTE least-privilege hardening (Issue #17).
--
-- Forward-only security migration. The baseline audit found 16 growth.*
-- functions relying on PostgreSQL's default EXECUTE-to-PUBLIC behavior.
-- Physical dependency inventory on the isolated Postgres-Validation cluster
-- proved which callers actually require EXECUTE after PUBLIC is removed.
--
-- Execution identity: growth_migrator. It owns all 16 functions below.
-- Owner EXECUTE is intrinsic in PostgreSQL and therefore is not duplicated
-- with an explicit GRANT to growth_migrator.
--
-- Explicit non-owner grants retained by design:
--   app_runtime:
--     current_app_user_id()
--     current_workspace_id()
--     content_version_visible(uuid,uuid)
--     assert_confirmed_insight_evidence_purity(uuid,uuid)
--   growth_rls_helper:
--     current_app_user_id()
--     current_workspace_id()
--   growth_identity_helper:
--     current_app_user_id()
--     current_workspace_id()
--
-- No production application role receives EXECUTE on the remaining internal
-- trigger/constraint functions. Trigger invocation itself does not require a
-- caller-side direct function API grant; nested helper calls are granted above
-- only where physical tests proved they are required.

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  missing_count integer;
  wrong_owner_count integer;
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
  )
  SELECT count(*) INTO missing_count
  FROM expected
  WHERE to_regprocedure(identity) IS NULL;

  IF missing_count <> 0 THEN
    RAISE EXCEPTION 'Issue #17 hardening aborted: one or more reviewed functions are missing';
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
    RAISE EXCEPTION 'Issue #17 hardening aborted: reviewed function ownership differs from dependency inventory';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_rls_helper')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_identity_helper') THEN
    RAISE EXCEPTION 'Issue #17 hardening aborted: required runtime/helper role is missing';
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION growth.assert_confirmed_insight_evidence_purity(uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.check_authority_history_projection_consistency() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.check_insight_evidence_purity() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.check_insight_state_evidence_purity() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.check_managed_account_projection_consistency() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.content_approval_assign_decision_no() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.content_version_visible(uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.current_app_user_id() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.current_workspace_id() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.enforce_deletion_request_state_transition() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.enforce_experiment_outcome_temporal_integrity() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.enforce_experiment_temporal_integrity() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.enforce_exposure_temporal_integrity() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.invalidate_metric_completeness_on_late_observation() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.reject_insight_demotion_cycle() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION growth.reject_mutation_while_retained() FROM PUBLIC;

-- Direct RLS/session-context consumers.
GRANT EXECUTE ON FUNCTION growth.current_app_user_id()
  TO app_runtime, growth_rls_helper, growth_identity_helper;
GRANT EXECUTE ON FUNCTION growth.current_workspace_id()
  TO app_runtime, growth_rls_helper, growth_identity_helper;

-- RLS policies on content_approvals/content_localizations/media_assets are
-- evaluated by app_runtime directly. growth_migrator remains able to call the
-- function as its owner, including inside SECURITY DEFINER content lifecycle
-- functions that encounter FORCE RLS.
GRANT EXECUTE ON FUNCTION growth.content_version_visible(uuid,uuid)
  TO app_runtime;

-- Deferred evidence-purity trigger functions are invoker-security and call this
-- helper under the DML caller's role. Physical validation proved app_runtime
-- therefore requires this narrow explicit grant.
GRANT EXECUTE ON FUNCTION growth.assert_confirmed_insight_evidence_purity(uuid,uuid)
  TO app_runtime;

COMMIT;
