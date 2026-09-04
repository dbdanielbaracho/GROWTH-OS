-- Growth OS — YouTube connector active-context hardening (Issue #26).
-- Applies after 010_youtube_connector_foundation.sql.
--
-- The OAuth callback intentionally does not depend on the browser session: it
-- reconstructs the tenant/user context from authenticated, expiring OAuth
-- state. Because growth.tenant_context_valid() validates tenant membership but
-- does not itself require users.status/workspaces.status to remain active,
-- provider credential writes receive this additional fail-closed guard.
--
-- This migration deliberately does NOT add a second collection-run ledger.
-- The API's caller-persisted requestNonce is the collection_run_id for the
-- first slice, and each observation already records a SHA-256 response digest
-- in raw_payload_ref plus a strict idempotency key. A durable job/run ledger can
-- be added later when scheduled/background ingestion is introduced.

\set ON_ERROR_STOP on

BEGIN;
SET search_path = growth, public;

CREATE FUNCTION growth.provider_credential_active_context_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  actor uuid := growth.current_app_user_id();
  ws uuid := growth.current_workspace_id();
BEGIN
  IF actor IS NULL OR ws IS NULL OR NEW.workspace_id IS DISTINCT FROM ws THEN
    RAISE EXCEPTION 'provider credential write requires matching tenant context';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM growth.users u
    WHERE u.id = actor
      AND u.status = 'active'
  ) THEN
    RAISE EXCEPTION 'provider credential write requires active user';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM growth.workspaces w
    WHERE w.id = ws
      AND w.status = 'active'
  ) THEN
    RAISE EXCEPTION 'provider credential write requires active workspace';
  END IF;

  IF NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'provider credential write requires active membership';
  END IF;

  RETURN NEW;
END;
$$;

ALTER FUNCTION growth.provider_credential_active_context_guard() OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.provider_credential_active_context_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.provider_credential_active_context_guard() FROM app_runtime;

CREATE TRIGGER provider_credentials_active_context
BEFORE INSERT OR UPDATE ON growth.provider_credentials
FOR EACH ROW EXECUTE FUNCTION growth.provider_credential_active_context_guard();

COMMIT;
