-- Publication cancellation contract + operational state-transition gate.
-- The physical proof is fully transactional, performs no provider call and
-- rolls back every temporary row before returning PASS.
\set ON_ERROR_STOP on

BEGIN;

DO $cancel_gate$
DECLARE
  cancel_oid oid;
  cancel_def text;
  helper_owner text;
  is_definer boolean;
  app_execute boolean;
  public_execute boolean;
BEGIN
  cancel_oid := to_regprocedure('growth.cancel_publication_intent(uuid,uuid,uuid)');
  IF cancel_oid IS NULL THEN
    RAISE EXCEPTION '045 failed: cancellation helper is missing';
  END IF;

  SELECT pg_get_functiondef(cancel_oid) INTO cancel_def;
  IF position('security definer' IN lower(cancel_def)) = 0
     OR position('sending' IN lower(cancel_def)) = 0
     OR position('confirmed' IN lower(cancel_def)) = 0
     OR position('cancelled_by' IN lower(cancel_def)) = 0
     OR position('app.user_id' IN lower(cancel_def)) = 0
  THEN
    RAISE EXCEPTION '045 failed: cancellation helper lacks actor/state guards';
  END IF;

  SELECT r.rolname, p.prosecdef
    INTO helper_owner, is_definer
  FROM pg_proc p
  JOIN pg_roles r ON r.oid = p.proowner
  WHERE p.oid = cancel_oid;

  IF helper_owner <> 'growth_migrator' OR is_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION '045 failed: cancellation helper owner/SECURITY DEFINER boundary';
  END IF;

  SELECT has_function_privilege('app_runtime', cancel_oid, 'EXECUTE')
    INTO app_execute;
  IF app_execute IS DISTINCT FROM true THEN
    RAISE EXCEPTION '045 failed: app_runtime cannot execute cancellation helper';
  END IF;

  SELECT has_function_privilege('public', cancel_oid, 'EXECUTE')
    INTO public_execute;
  IF public_execute IS DISTINCT FROM false THEN
    RAISE EXCEPTION '045 failed: PUBLIC can execute cancellation helper';
  END IF;
END;
$cancel_gate$;

DO $seed_cancellation_smoke$
DECLARE
  workspace_id uuid := 'f0450000-0000-4000-8000-000000000001';
  user_id uuid := 'f0450000-0000-4000-8000-000000000002';
  managed_account_id uuid := 'f0450000-0000-4000-8000-000000000003';
  connection_id uuid := 'f0450000-0000-4000-8000-000000000004';
  social_account_id uuid := 'f0450000-0000-4000-8000-000000000005';
  scheduled_item_id uuid := 'f0450000-0000-4000-8000-000000000006';
  scheduled_version_id uuid := 'f0450000-0000-4000-8000-000000000007';
  scheduled_intent_id uuid := 'f0450000-0000-4000-8000-000000000008';
  confirmed_item_id uuid := 'f0450000-0000-4000-8000-000000000009';
  confirmed_version_id uuid := 'f0450000-0000-4000-8000-000000000010';
  confirmed_intent_id uuid := 'f0450000-0000-4000-8000-000000000011';
BEGIN
  INSERT INTO growth.workspaces(
    id, name, default_market, default_language, default_timezone, status
  ) VALUES (
    workspace_id, 'gate-045-cancellation', 'US', 'en', 'UTC', 'active'
  );

  INSERT INTO growth.users(id, email, status)
  VALUES(user_id, 'gate-045-cancellation@example.invalid', 'active');

  INSERT INTO growth.memberships(
    workspace_id, user_id, role, can_publish, status
  ) VALUES (
    workspace_id, user_id, 'owner', true, 'active'
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
    'gate_test', 'gate-045-provider-account', 'gate045', 'test', 'US', 'UTC'
  );

  INSERT INTO growth.content_items(
    id, workspace_id, objective, market, language, platform_target,
    source_type, status, created_by
  ) VALUES
  (
    scheduled_item_id, workspace_id, 'cancellation smoke scheduled', 'US', 'en',
    'gate_test', 'manual', 'approved', user_id
  ),
  (
    confirmed_item_id, workspace_id, 'cancellation smoke confirmed', 'US', 'en',
    'gate_test', 'manual', 'approved', user_id
  );

  INSERT INTO growth.content_versions(
    id, workspace_id, content_item_id, version_no, body, checksum
  ) VALUES
  (
    scheduled_version_id, workspace_id, scheduled_item_id, 1,
    'rollback-only cancellation smoke scheduled', 'gate-045-cancel-scheduled'
  ),
  (
    confirmed_version_id, workspace_id, confirmed_item_id, 1,
    'rollback-only cancellation smoke confirmed', 'gate-045-cancel-confirmed'
  );

  INSERT INTO growth.publication_intents(
    id, workspace_id, social_account_id, content_version_id,
    request_nonce, idempotency_key, status, scheduled_for
  ) VALUES
  (
    scheduled_intent_id, workspace_id, social_account_id, scheduled_version_id,
    'f0450000-0000-4000-8000-000000000012',
    'gate-045-cancel-scheduled-intent', 'scheduled', now() + interval '1 day'
  ),
  (
    confirmed_intent_id, workspace_id, social_account_id, confirmed_version_id,
    'f0450000-0000-4000-8000-000000000013',
    'gate-045-cancel-confirmed-intent', 'confirmed', NULL
  );
END;
$seed_cancellation_smoke$;

SET LOCAL ROLE app_runtime;
SELECT set_config('app.workspace_id', 'f0450000-0000-4000-8000-000000000001', true);
SELECT set_config('app.user_id', 'f0450000-0000-4000-8000-000000000002', true);

DO $actor_boundary_smoke$
BEGIN
  BEGIN
    PERFORM growth.cancel_publication_intent(
      'f0450000-0000-4000-8000-000000000001',
      'f0450000-0000-4000-8000-000000000008',
      'f0450000-0000-4000-8000-000000000099'
    );
    RAISE EXCEPTION '045 failed: cancellation accepted a different actor';
  EXCEPTION
    WHEN OTHERS THEN
      IF position('active actor context' IN SQLERRM) = 0 THEN
        RAISE;
      END IF;
  END;
END;
$actor_boundary_smoke$;

SELECT growth.cancel_publication_intent(
  'f0450000-0000-4000-8000-000000000001',
  'f0450000-0000-4000-8000-000000000008',
  'f0450000-0000-4000-8000-000000000002'
);

DO $terminal_state_smoke$
BEGIN
  BEGIN
    PERFORM growth.cancel_publication_intent(
      'f0450000-0000-4000-8000-000000000001',
      'f0450000-0000-4000-8000-000000000008',
      'f0450000-0000-4000-8000-000000000002'
    );
    RAISE EXCEPTION '045 failed: already-cancelled intent was cancelled again';
  EXCEPTION
    WHEN OTHERS THEN
      IF position('cannot be cancelled from status cancelled' IN SQLERRM) = 0 THEN
        RAISE;
      END IF;
  END;

  BEGIN
    PERFORM growth.cancel_publication_intent(
      'f0450000-0000-4000-8000-000000000001',
      'f0450000-0000-4000-8000-000000000011',
      'f0450000-0000-4000-8000-000000000002'
    );
    RAISE EXCEPTION '045 failed: confirmed intent was cancellable';
  EXCEPTION
    WHEN OTHERS THEN
      IF position('cannot be cancelled from status confirmed' IN SQLERRM) = 0 THEN
        RAISE;
      END IF;
  END;
END;
$terminal_state_smoke$;

RESET ROLE;

DO $verify_cancellation_smoke$
DECLARE
  cancelled_status text;
  cancelled_actor uuid;
  cancelled_time timestamptz;
  scheduled_time timestamptz;
  confirmed_status text;
BEGIN
  SELECT status, cancelled_by, cancelled_at, scheduled_for
    INTO cancelled_status, cancelled_actor, cancelled_time, scheduled_time
  FROM growth.publication_intents
  WHERE id = 'f0450000-0000-4000-8000-000000000008';

  IF cancelled_status IS DISTINCT FROM 'cancelled'
     OR cancelled_actor IS DISTINCT FROM 'f0450000-0000-4000-8000-000000000002'::uuid
     OR cancelled_time IS NULL
     OR scheduled_time IS NOT NULL
  THEN
    RAISE EXCEPTION '045 failed: valid cancellation did not persist the bounded cancellation state';
  END IF;

  SELECT status INTO confirmed_status
  FROM growth.publication_intents
  WHERE id = 'f0450000-0000-4000-8000-000000000011';

  IF confirmed_status IS DISTINCT FROM 'confirmed' THEN
    RAISE EXCEPTION '045 failed: blocked confirmed cancellation mutated the intent';
  END IF;
END;
$verify_cancellation_smoke$;

ROLLBACK;

SELECT 'TEST-045 PASS: actor mismatch rejected; scheduled -> cancelled; cancelled/confirmed blocked; rollback complete' AS result;
