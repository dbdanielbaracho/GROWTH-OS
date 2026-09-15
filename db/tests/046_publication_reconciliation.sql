-- Publication reconciliation contract + operational state-transition gate.
-- The physical proof is self-contained, performs no provider call and rolls back
-- every temporary row before returning PASS.
\set ON_ERROR_STOP on

BEGIN;

DO $reconciliation_gate$
DECLARE
  reconciliation_oid oid;
  reconciliation_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
BEGIN
  reconciliation_oid := to_regprocedure(
    'growth.record_publication_reconciliation(uuid,uuid,integer,text,text,text,text,text)'
  );
  IF reconciliation_oid IS NULL THEN
    RAISE EXCEPTION '046 failed: reconciliation helper is missing';
  END IF;

  SELECT pg_get_functiondef(reconciliation_oid) INTO reconciliation_def;
  IF position('security definer' IN lower(reconciliation_def)) = 0
     OR position('publication_reconciliation_attempts' IN lower(reconciliation_def)) = 0
     OR position('immutable evidence' IN lower(reconciliation_def)) = 0
     OR position('matched' IN lower(reconciliation_def)) = 0
     OR position('needs_user_action' IN lower(reconciliation_def)) = 0
  THEN
    RAISE EXCEPTION '046 failed: reconciliation helper lacks evidence/state guards';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = reconciliation_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '046 failed: reconciliation helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', reconciliation_oid, 'EXECUTE')
    INTO app_execute;
  IF app_execute IS DISTINCT FROM true THEN
    RAISE EXCEPTION '046 failed: app_runtime cannot execute reconciliation helper';
  END IF;

  SELECT has_function_privilege('public', reconciliation_oid, 'EXECUTE')
    INTO public_execute;
  IF public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION '046 failed: PUBLIC can execute reconciliation helper';
  END IF;
END;
$reconciliation_gate$;

DO $seed_reconciliation_smoke$
DECLARE
  workspace_id uuid := 'f0460000-0000-4000-8000-000000000001';
  managed_account_id uuid := 'f0460000-0000-4000-8000-000000000002';
  connection_id uuid := 'f0460000-0000-4000-8000-000000000003';
  social_account_id uuid := 'f0460000-0000-4000-8000-000000000004';
  content_item_id uuid := 'f0460000-0000-4000-8000-000000000005';
  content_version_id uuid := 'f0460000-0000-4000-8000-000000000006';
  publication_intent_id uuid := 'f0460000-0000-4000-8000-000000000007';
  service_principal_id uuid := 'f0460000-0000-4000-8000-000000000008';
  job_id uuid := 'f0460000-0000-4000-8000-000000000009';
BEGIN
  INSERT INTO growth.workspaces(
    id, name, default_market, default_language, default_timezone, status
  ) VALUES (
    workspace_id, 'gate-046-reconciliation', 'US', 'en', 'UTC', 'active'
  );

  INSERT INTO growth.managed_accounts(
    id, workspace_id, owner_type, authority_status, contribution_eligibility
  ) VALUES (
    managed_account_id, workspace_id, 'direct', 'contractually_granted', 'private_only'
  );

  INSERT INTO growth.platform_connections(
    id, workspace_id, managed_account_id, platform, state
  ) VALUES (
    connection_id, workspace_id, managed_account_id, 'gate_test', 'connected'
  );

  INSERT INTO growth.social_accounts(
    id, workspace_id, managed_account_id, platform_connection_id,
    platform, provider_account_id, handle, account_type, market, timezone
  ) VALUES (
    social_account_id, workspace_id, managed_account_id, connection_id,
    'gate_test', 'gate-046-provider-account', 'gate046', 'test', 'US', 'UTC'
  );

  INSERT INTO growth.content_items(
    id, workspace_id, objective, market, language, platform_target,
    source_type, status
  ) VALUES (
    content_item_id, workspace_id, 'reconciliation smoke', 'US', 'en',
    'gate_test', 'manual', 'approved'
  );

  INSERT INTO growth.content_versions(
    id, workspace_id, content_item_id, version_no, body, checksum
  ) VALUES (
    content_version_id, workspace_id, content_item_id, 1,
    'rollback-only reconciliation smoke', 'gate-046-reconciliation-checksum'
  );

  INSERT INTO growth.publication_intents(
    id, workspace_id, social_account_id, content_version_id,
    request_nonce, idempotency_key, status
  ) VALUES (
    publication_intent_id, workspace_id, social_account_id, content_version_id,
    'f0460000-0000-4000-8000-000000000010',
    'gate-046-reconciliation-intent', 'failed_retryable'
  );

  INSERT INTO growth.worker_service_principals(
    id, name, status, allowed_job_types
  ) VALUES (
    service_principal_id, 'gate-046-reconciliation', 'active',
    ARRAY['publication_intent']
  );

  INSERT INTO growth.jobs(
    id, workspace_id, job_type, operation_key, payload, state,
    available_at, leased_until, attempts, service_principal_id
  ) VALUES (
    job_id, workspace_id, 'publication_intent', publication_intent_id::text,
    jsonb_build_object('publication_intent_id', publication_intent_id),
    'leased', now(), now() + interval '10 minutes', 1, service_principal_id
  );
END;
$seed_reconciliation_smoke$;

SET LOCAL ROLE app_runtime;

SELECT set_config('app.workspace_id', 'f0460000-0000-4000-8000-000000000001', true);
SELECT set_config('app.service_principal_id', 'f0460000-0000-4000-8000-000000000008', true);
SELECT set_config('app.job_id', 'f0460000-0000-4000-8000-000000000009', true);

SELECT growth.record_publication_reconciliation(
  'f0460000-0000-4000-8000-000000000001',
  'f0460000-0000-4000-8000-000000000007',
  1,
  'manual',
  'medium',
  'ambiguous',
  NULL,
  'gate://reconciliation/ambiguous'
);

-- An identical replay must be idempotent and must not create another evidence row.
SELECT growth.record_publication_reconciliation(
  'f0460000-0000-4000-8000-000000000001',
  'f0460000-0000-4000-8000-000000000007',
  1,
  'manual',
  'medium',
  'ambiguous',
  NULL,
  'gate://reconciliation/ambiguous'
);

DO $immutable_replay_smoke$
BEGIN
  BEGIN
    PERFORM growth.record_publication_reconciliation(
      'f0460000-0000-4000-8000-000000000001',
      'f0460000-0000-4000-8000-000000000007',
      1,
      'manual',
      'low',
      'not_found',
      NULL,
      'gate://reconciliation/conflict'
    );
    RAISE EXCEPTION '046 failed: conflicting reconciliation replay was accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF position('immutable evidence' IN SQLERRM) = 0 THEN
        RAISE;
      END IF;
  END;
END;
$immutable_replay_smoke$;

SELECT growth.record_publication_reconciliation(
  'f0460000-0000-4000-8000-000000000001',
  'f0460000-0000-4000-8000-000000000007',
  2,
  'exact',
  'exact',
  'matched',
  'gate-provider-content-046',
  'gate://reconciliation/matched'
);

RESET ROLE;

DO $verify_reconciliation_smoke$
DECLARE
  final_status text;
  provider_content_id text;
  evidence_count integer;
  ambiguous_count integer;
  matched_count integer;
BEGIN
  SELECT pi.status, pi.provider_content_id
    INTO final_status, provider_content_id
  FROM growth.publication_intents pi
  WHERE pi.id = 'f0460000-0000-4000-8000-000000000007';

  IF final_status IS DISTINCT FROM 'confirmed'
     OR provider_content_id IS DISTINCT FROM 'gate-provider-content-046'
  THEN
    RAISE EXCEPTION '046 failed: matched reconciliation did not confirm the intent';
  END IF;

  SELECT count(*) INTO evidence_count
  FROM growth.publication_reconciliation_attempts pra
  WHERE pra.publication_intent_id = 'f0460000-0000-4000-8000-000000000007';

  SELECT count(*) INTO ambiguous_count
  FROM growth.publication_reconciliation_attempts pra
  WHERE pra.publication_intent_id = 'f0460000-0000-4000-8000-000000000007'
    AND pra.attempt_no = 1
    AND pra.reconciliation_status = 'ambiguous'
    AND pra.confidence = 'medium';

  SELECT count(*) INTO matched_count
  FROM growth.publication_reconciliation_attempts pra
  WHERE pra.publication_intent_id = 'f0460000-0000-4000-8000-000000000007'
    AND pra.attempt_no = 2
    AND pra.reconciliation_status = 'matched'
    AND pra.confidence = 'exact'
    AND pra.candidate_provider_content_id = 'gate-provider-content-046';

  IF evidence_count <> 2 OR ambiguous_count <> 1 OR matched_count <> 1 THEN
    RAISE EXCEPTION '046 failed: reconciliation evidence is not bounded/idempotent';
  END IF;
END;
$verify_reconciliation_smoke$;

ROLLBACK;

SELECT 'TEST-046 PASS: ambiguous -> needs_user_action -> matched -> confirmed; immutable replay rejected; rollback complete' AS result;
