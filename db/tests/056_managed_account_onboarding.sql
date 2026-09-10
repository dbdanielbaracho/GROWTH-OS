-- Growth OS — managed-account onboarding regression gate.
-- Runs in the disposable CI database only.

\set ON_ERROR_STOP on

BEGIN;
SET search_path = growth, public;

INSERT INTO growth.users(
  id,
  email,
  status,
  email_verified_at
)
VALUES (
  'a0000000-0000-4000-8000-000000000004',
  'managed-account-onboarding@example.test',
  'active',
  now()
)
ON CONFLICT (id) DO UPDATE
SET status = 'active',
    email_verified_at = now();

SELECT set_config(
  'app.user_id',
  'a0000000-0000-4000-8000-000000000004',
  true
);

SET ROLE app_runtime;

SELECT growth.identity_create_workspace(
  'Managed Account Onboarding Test',
  'US',
  'en',
  'UTC'
) AS workspace_id
\gset

RESET ROLE;
SELECT set_config('test.workspace_id', :'workspace_id', true);

DO $$
DECLARE
  managed_count integer;
  authority_count integer;
  account_row record;
BEGIN
  SELECT count(*)::integer INTO managed_count
  FROM growth.managed_accounts
  WHERE workspace_id = current_setting('test.workspace_id')::uuid;

  IF managed_count <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL: expected exactly one managed account, got %', managed_count;
  END IF;

  SELECT count(*)::integer INTO authority_count
  FROM growth.authority_history
  WHERE workspace_id = current_setting('test.workspace_id')::uuid
    AND managed_account_id IN (
      SELECT id
      FROM growth.managed_accounts
      WHERE workspace_id = current_setting('test.workspace_id')::uuid
    )
    AND effective_to IS NULL;

  IF authority_count <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL: expected one open authority row, got %', authority_count;
  END IF;

  SELECT ma.* INTO account_row
  FROM growth.managed_accounts ma
  WHERE ma.workspace_id = current_setting('test.workspace_id')::uuid;

  IF account_row.owner_type <> 'direct'
     OR account_row.authority_status <> 'contractually_granted'
     OR account_row.contribution_eligibility <> 'private_only'
     OR account_row.authority_clause_ref <> 'workspace-owner-self-managed-v1' THEN
    RAISE EXCEPTION 'TEST FAIL: default authority contract is incorrect';
  END IF;
END
$$;

ROLLBACK;

\echo 'PASS: managed-account onboarding creates a direct private account with matching authority history'
