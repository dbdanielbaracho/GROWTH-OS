-- Growth OS — managed-account onboarding repair.
-- A workspace owner needs a direct, private managed-account authority record
-- before a provider OAuth flow can be started. OAuth consent alone still never
-- creates provider authority or bypasses the managed-account guard.
--
-- This migration:
--   1. adds an idempotent SECURITY DEFINER helper owned by the identity role;
--   2. creates the default direct/private managed account during workspace creation;
--   3. backfills active workspaces that have no managed account;
--   4. keeps contribution eligibility private_only and never enables publishing
--      or insights.

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'growth_identity_helper'
  ) THEN
    RAISE EXCEPTION 'growth_identity_helper is required';
  END IF;
END $$;

GRANT USAGE ON SCHEMA growth TO growth_identity_helper;
GRANT SELECT, INSERT ON growth.managed_accounts, growth.authority_history
  TO growth_identity_helper;

CREATE OR REPLACE FUNCTION growth.ensure_direct_managed_account(
  p_workspace_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  existing_id uuid;
  managed_id uuid := gen_random_uuid();
  authority_ref constant text := 'workspace-owner-self-managed-v1';
BEGIN
  IF p_workspace_id IS NULL THEN
    RAISE EXCEPTION 'workspace id is required';
  END IF;

  SELECT ma.id
    INTO existing_id
  FROM growth.managed_accounts ma
  WHERE ma.workspace_id = p_workspace_id
  ORDER BY ma.created_at, ma.id
  LIMIT 1;

  IF existing_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM growth.authority_history ah
      WHERE ah.workspace_id = p_workspace_id
        AND ah.managed_account_id = existing_id
        AND ah.effective_to IS NULL
    ) THEN
      RAISE EXCEPTION 'managed account % has no open authority history', existing_id;
    END IF;
    RETURN existing_id;
  END IF;

  INSERT INTO growth.managed_accounts(
    id,
    workspace_id,
    owner_type,
    authority_status,
    contribution_eligibility,
    authority_clause_ref
  )
  VALUES (
    managed_id,
    p_workspace_id,
    'direct',
    'contractually_granted',
    'private_only',
    authority_ref
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
    gen_random_uuid(),
    p_workspace_id,
    managed_id,
    'direct',
    'contractually_granted',
    'private_only',
    authority_ref,
    now()
  );

  RETURN managed_id;
END;
$$;

ALTER FUNCTION growth.ensure_direct_managed_account(uuid)
  OWNER TO growth_identity_helper;
REVOKE ALL ON FUNCTION growth.ensure_direct_managed_account(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION growth.identity_create_workspace(
  p_name text,
  p_default_market text,
  p_default_language text,
  p_default_timezone text
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  actor uuid := growth.current_app_user_id();
  workspace_id uuid := gen_random_uuid();
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM growth.users
    WHERE id = actor
      AND status = 'active'
      AND email_verified_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'verified active user required';
  END IF;

  IF btrim(p_name) = ''
     OR btrim(p_default_market) = ''
     OR btrim(p_default_language) = ''
     OR btrim(p_default_timezone) = '' THEN
    RAISE EXCEPTION 'workspace fields are required';
  END IF;

  PERFORM set_config('app.workspace_id', workspace_id::text, true);

  INSERT INTO growth.workspaces(
    id,
    name,
    default_market,
    default_language,
    default_timezone,
    status
  )
  VALUES (
    workspace_id,
    btrim(p_name),
    p_default_market,
    p_default_language,
    p_default_timezone,
    'active'
  );

  INSERT INTO growth.memberships(
    workspace_id,
    user_id,
    role,
    can_publish,
    status
  )
  VALUES (workspace_id, actor, 'owner', true, 'active');

  PERFORM growth.ensure_direct_managed_account(workspace_id);

  INSERT INTO growth.audit_events(
    id,
    workspace_id,
    actor_user_id,
    event_type,
    resource_type,
    resource_id
  )
  VALUES (
    gen_random_uuid(),
    workspace_id,
    actor,
    'identity.workspace.created.v1',
    'workspace',
    workspace_id
  );

  RETURN workspace_id;
END;
$$;

ALTER FUNCTION growth.identity_create_workspace(text,text,text,text)
  OWNER TO growth_identity_helper;
REVOKE ALL ON FUNCTION growth.identity_create_workspace(text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.identity_create_workspace(text,text,text,text)
  TO app_runtime;

DO $$
DECLARE
  workspace_row record;
BEGIN
  FOR workspace_row IN
    SELECT w.id
    FROM growth.workspaces w
    WHERE w.status = 'active'
      AND EXISTS (
        SELECT 1
        FROM growth.memberships m
        WHERE m.workspace_id = w.id
          AND m.role = 'owner'
          AND m.status = 'active'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM growth.managed_accounts ma
        WHERE ma.workspace_id = w.id
      )
    ORDER BY w.id
  LOOP
    PERFORM growth.ensure_direct_managed_account(workspace_row.id);
  END LOOP;
END;
$$;

CREATE TABLE IF NOT EXISTS growth.managed_account_onboarding_046 (
  id boolean PRIMARY KEY DEFAULT true,
  completed_at timestamptz NOT NULL DEFAULT now(),
  CHECK (id)
);

INSERT INTO growth.managed_account_onboarding_046(id)
VALUES (true)
ON CONFLICT (id) DO NOTHING;

COMMIT;
