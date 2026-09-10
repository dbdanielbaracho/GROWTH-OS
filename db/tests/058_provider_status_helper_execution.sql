-- Growth OS — provider status helper execution regression gate.
-- Executes both route-facing helpers through app_runtime with a real tenant
-- context, proving the protected call chain works without direct table reads.

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO growth.managed_accounts(
  id,
  workspace_id,
  owner_type,
  authority_status,
  contribution_eligibility,
  authority_clause_ref
)
VALUES (
  'c0000000-0000-4000-8000-000000000001',
  'b0000000-0000-4000-8000-000000000001',
  'direct',
  'contractually_granted',
  'private_only',
  'provider-status-test-v1'
);

INSERT INTO growth.authority_history(
  id,
  workspace_id,
  managed_account_id,
  owner_type,
  authority_status,
  contribution_eligibility,
  authority_clause_ref,
  effective_from
)
VALUES (
  'c0000000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000001',
  'direct',
  'contractually_granted',
  'private_only',
  'provider-status-test-v1',
  now()
);

SELECT set_config(
  'app.user_id',
  'a0000000-0000-4000-8000-000000000001',
  false
);
SELECT set_config(
  'app.workspace_id',
  'b0000000-0000-4000-8000-000000000001',
  false
);

SET ROLE app_runtime;

SELECT count(*) >= 0 AS instagram_status_executes
FROM growth.instagram_integration_status();

SELECT count(*) >= 0 AS youtube_status_executes
FROM growth.youtube_integration_status();

RESET ROLE;

ROLLBACK;

\echo 'PASS: app_runtime can execute both provider status helpers through the full call chain'
