-- Growth OS — YouTube connector hardening/provenance (Issue #26).
-- Applies after 010_youtube_connector_foundation.sql.
\set ON_ERROR_STOP on

BEGIN;
SET search_path = growth, public;

-- Exact provider reporting date avoids pretending a provider-local day is an
-- exact UTC instant. observed_at/source_range remain available for generic
-- consumers; reporting_date preserves the original day semantics.
ALTER TABLE growth.metric_observations
  ADD COLUMN provider_reporting_date date;

-- Sanitized collection-run ledger: records what was requested and a response
-- digest, but never provider tokens/cookies/authorization codes or raw response
-- bodies. Observations reference this run through collection_run_id.
CREATE TABLE growth.provider_collection_runs (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  social_account_id uuid NOT NULL,
  provider text NOT NULL,
  provider_product text NOT NULL,
  request_nonce uuid NOT NULL,
  request_descriptor jsonb NOT NULL DEFAULT '{}'::jsonb,
  response_sha256 text,
  source_range_start date,
  source_range_end date,
  status text NOT NULL CHECK (status IN ('started','completed','failed')),
  error_class text,
  started_at timestamptz NOT NULL,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (source_range_end IS NULL OR source_range_start IS NULL OR source_range_end >= source_range_start),
  CHECK (completed_at IS NULL OR completed_at >= started_at),
  CHECK ((status='started' AND completed_at IS NULL)
      OR (status IN ('completed','failed') AND completed_at IS NOT NULL)),
  UNIQUE (workspace_id,provider,request_nonce),
  UNIQUE (workspace_id,id),
  FOREIGN KEY (workspace_id,social_account_id)
    REFERENCES growth.social_accounts(workspace_id,id)
);
ALTER TABLE growth.provider_collection_runs OWNER TO growth_migrator;
ALTER TABLE growth.provider_collection_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.provider_collection_runs FORCE ROW LEVEL SECURITY;
CREATE POLICY provider_collection_runs_workspace_isolation
  ON growth.provider_collection_runs
  USING (growth.tenant_context_valid(workspace_id))
  WITH CHECK (growth.tenant_context_valid(workspace_id));
REVOKE ALL ON TABLE growth.provider_collection_runs FROM PUBLIC;
REVOKE ALL ON TABLE growth.provider_collection_runs FROM app_runtime;

ALTER TABLE growth.metric_observations
  ADD CONSTRAINT metric_observations_collection_run_fk
  FOREIGN KEY (workspace_id,collection_run_id)
  REFERENCES growth.provider_collection_runs(workspace_id,id);

-- Defense in depth for the OAuth callback. The callback has no browser session;
-- it reconstructs tenant context from authenticated OAuth state. Before any
-- provider credential can be inserted/updated, independently require the user
-- and workspace represented by that context to remain active.
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
    SELECT 1 FROM growth.users u
    WHERE u.id=actor AND u.status='active'
  ) THEN
    RAISE EXCEPTION 'provider credential write requires active user';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.workspaces w
    WHERE w.id=ws AND w.status='active'
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

CREATE TRIGGER provider_credentials_active_context
BEFORE INSERT OR UPDATE ON growth.provider_credentials
FOR EACH ROW EXECUTE FUNCTION growth.provider_credential_active_context_guard();

-- Narrow collection-run helpers. app_runtime receives EXECUTE only.
CREATE FUNCTION growth.youtube_begin_collection_run(
  p_social_account_id uuid,
  p_request_nonce uuid,
  p_start_date date,
  p_end_date date,
  p_request_descriptor jsonb
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ws uuid := growth.current_workspace_id();
  run_id uuid;
BEGIN
  IF ws IS NULL OR growth.current_app_user_id() IS NULL OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'youtube collection requires active tenant context';
  END IF;
  IF p_end_date < p_start_date THEN
    RAISE EXCEPTION 'youtube collection range invalid';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM growth.social_accounts sa
    JOIN growth.platform_connections pc
      ON pc.workspace_id=sa.workspace_id AND pc.id=sa.platform_connection_id
    JOIN growth.managed_accounts ma
      ON ma.workspace_id=sa.workspace_id AND ma.id=sa.managed_account_id
    JOIN growth.users u ON u.id=growth.current_app_user_id()
    JOIN growth.workspaces w ON w.id=sa.workspace_id
    WHERE sa.workspace_id=ws AND sa.id=p_social_account_id
      AND sa.platform='youtube' AND pc.state='connected'
      AND ma.authority_status='contractually_granted'
      AND u.status='active' AND w.status='active'
  ) THEN
    RAISE EXCEPTION 'youtube collection requires connected active authorized account';
  END IF;

  SELECT r.id INTO run_id
  FROM growth.provider_collection_runs r
  WHERE r.workspace_id=ws AND r.provider='youtube' AND r.request_nonce=p_request_nonce
  FOR UPDATE;

  IF run_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM growth.provider_collection_runs r
      WHERE r.id=run_id
        AND r.social_account_id=p_social_account_id
        AND r.provider_product='youtube_analytics'
        AND r.source_range_start=p_start_date
        AND r.source_range_end=p_end_date
        AND r.request_descriptor=p_request_descriptor
    ) THEN
      RAISE EXCEPTION 'youtube collection request nonce conflict';
    END IF;
    RETURN run_id;
  END IF;

  run_id := gen_random_uuid();
  INSERT INTO growth.provider_collection_runs(
    id,workspace_id,social_account_id,provider,provider_product,request_nonce,
    request_descriptor,source_range_start,source_range_end,status,started_at
  ) VALUES (
    run_id,ws,p_social_account_id,'youtube','youtube_analytics',p_request_nonce,
    p_request_descriptor,p_start_date,p_end_date,'started',now()
  );
  RETURN run_id;
END;
$$;
ALTER FUNCTION growth.youtube_begin_collection_run(uuid,uuid,date,date,jsonb) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.youtube_begin_collection_run(uuid,uuid,date,date,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.youtube_begin_collection_run(uuid,uuid,date,date,jsonb) TO app_runtime;

CREATE FUNCTION growth.youtube_complete_collection_run(
  p_run_id uuid,
  p_response_sha256 text
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE ws uuid := growth.current_workspace_id();
BEGIN
  IF ws IS NULL OR growth.current_app_user_id() IS NULL OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'youtube collection completion requires active tenant context';
  END IF;
  IF p_response_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'youtube collection response digest invalid';
  END IF;

  UPDATE growth.provider_collection_runs
  SET status='completed',response_sha256=p_response_sha256,completed_at=now(),error_class=NULL
  WHERE workspace_id=ws AND id=p_run_id
    AND provider='youtube'
    AND status IN ('started','completed')
    AND (response_sha256 IS NULL OR response_sha256=p_response_sha256);
  RETURN FOUND;
END;
$$;
ALTER FUNCTION growth.youtube_complete_collection_run(uuid,text) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.youtube_complete_collection_run(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.youtube_complete_collection_run(uuid,text) TO app_runtime;

CREATE FUNCTION growth.youtube_fail_collection_run(
  p_run_id uuid,
  p_error_class text
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE ws uuid := growth.current_workspace_id();
BEGIN
  IF ws IS NULL OR growth.current_app_user_id() IS NULL OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'youtube collection failure record requires active tenant context';
  END IF;
  UPDATE growth.provider_collection_runs
  SET status='failed',completed_at=now(),error_class=left(nullif(btrim(p_error_class),''),120)
  WHERE workspace_id=ws AND id=p_run_id AND provider='youtube' AND status='started';
  RETURN FOUND;
END;
$$;
ALTER FUNCTION growth.youtube_fail_collection_run(uuid,text) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.youtube_fail_collection_run(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.youtube_fail_collection_run(uuid,text) TO app_runtime;

COMMIT;
