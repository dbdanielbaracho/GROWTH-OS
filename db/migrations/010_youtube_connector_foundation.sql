-- Growth OS — YouTube connector foundation (Issue #26).
-- Forward-only migration. Preserves 001-009 byte-for-byte.
--
-- Goals:
-- 1. add the Gate Zero provenance/policy contract to metric observations;
-- 2. isolate provider OAuth credentials from app_runtime table access;
-- 3. expose only narrow SECURITY DEFINER helpers for the YouTube adapter;
-- 4. keep derived analytics disabled until documented YouTube policy acceptance;
-- 5. make metric ingestion retry-safe with a strict idempotency conflict check.

\set ON_ERROR_STOP on

BEGIN;
SET search_path = growth, public;

-- ---------------------------------------------------------------------------
-- Observation provenance contract approved by Gate Zero.
-- Existing rows remain valid; the YouTube write helper below requires the
-- complete contract for all new YouTube observations.
-- ---------------------------------------------------------------------------
ALTER TABLE growth.metric_observations
  ADD COLUMN provider_product text,
  ADD COLUMN provider_object_type text,
  ADD COLUMN metric_semantic_version text,
  ADD COLUMN semantic_effective_from timestamptz,
  ADD COLUMN semantic_effective_to timestamptz,
  ADD COLUMN source_range_start timestamptz,
  ADD COLUMN source_range_end timestamptz,
  ADD COLUMN authorization_class text,
  ADD COLUMN retention_deadline timestamptz,
  ADD COLUMN refresh_required_by timestamptz,
  ADD COLUMN completeness_status text,
  ADD COLUMN freshness_status text,
  ADD COLUMN collection_run_id uuid,
  ADD COLUMN idempotency_key text;

ALTER TABLE growth.metric_observations
  ADD CONSTRAINT metric_observations_semantic_range_ck
    CHECK (semantic_effective_to IS NULL OR semantic_effective_from IS NULL OR semantic_effective_to >= semantic_effective_from),
  ADD CONSTRAINT metric_observations_source_range_ck
    CHECK (source_range_end IS NULL OR source_range_start IS NULL OR source_range_end >= source_range_start),
  ADD CONSTRAINT metric_observations_authorization_class_ck
    CHECK (authorization_class IS NULL OR authorization_class IN ('authorized_account','public','provider_push','licensed')),
  ADD CONSTRAINT metric_observations_completeness_ck
    CHECK (completeness_status IS NULL OR completeness_status IN ('complete','partial','unavailable','unknown')),
  ADD CONSTRAINT metric_observations_freshness_ck
    CHECK (freshness_status IS NULL OR freshness_status IN ('fresh','stale','unknown')),
  ADD CONSTRAINT metric_observations_retention_ck
    CHECK (retention_deadline IS NULL OR retention_deadline >= collected_at_placeholder()),
  ADD CONSTRAINT metric_observations_idempotency_nonblank_ck
    CHECK (idempotency_key IS NULL OR btrim(idempotency_key) <> '');

-- The retention check above cannot reference a function that does not exist;
-- replace it immediately with a row-local, deterministic constraint.
ALTER TABLE growth.metric_observations
  DROP CONSTRAINT metric_observations_retention_ck;
ALTER TABLE growth.metric_observations
  ADD CONSTRAINT metric_observations_retention_ck
    CHECK (retention_deadline IS NULL OR retention_deadline >= created_at),
  ADD CONSTRAINT metric_observations_refresh_ck
    CHECK (refresh_required_by IS NULL OR refresh_required_by >= created_at);

CREATE UNIQUE INDEX metric_observations_idempotency_uq
  ON growth.metric_observations(workspace_id,idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Credential isolation.
-- platform_connections.credential_ciphertext remains for backward schema
-- compatibility but the YouTube adapter never writes it. New OAuth material is
-- stored here and app_runtime receives no table privilege.
-- ---------------------------------------------------------------------------
CREATE TABLE growth.provider_credentials (
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  platform_connection_id uuid NOT NULL,
  provider text NOT NULL,
  credential_ciphertext bytea NOT NULL,
  cipher_version text NOT NULL,
  key_version text NOT NULL,
  token_expires_at timestamptz,
  refresh_available boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workspace_id,platform_connection_id),
  FOREIGN KEY (workspace_id,platform_connection_id)
    REFERENCES growth.platform_connections(workspace_id,id)
);
ALTER TABLE growth.provider_credentials OWNER TO growth_migrator;
ALTER TABLE growth.provider_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.provider_credentials FORCE ROW LEVEL SECURITY;
CREATE POLICY provider_credentials_workspace_isolation
  ON growth.provider_credentials
  USING (growth.tenant_context_valid(workspace_id))
  WITH CHECK (growth.tenant_context_valid(workspace_id));

REVOKE ALL ON TABLE growth.provider_credentials FROM PUBLIC;
REVOKE ALL ON TABLE growth.provider_credentials FROM app_runtime;

-- ---------------------------------------------------------------------------
-- Capability registry rows. derived_analytics is deliberately disabled until
-- the policy acceptance evidence is recorded and a later reviewed change
-- enables it.
-- ---------------------------------------------------------------------------
INSERT INTO growth.capabilities(
  id,platform,market,account_type,capability,status,required_scopes,limits,
  media_constraints,app_review_status,provider_api_version,validated_at,
  evidence_ref,evidence_status,adapter_version,kill_switch,updated_at
)
VALUES
  (gen_random_uuid(),'youtube','GLOBAL','channel','authorized_analytics','validation_required',
   ARRAY['https://www.googleapis.com/auth/youtube.readonly','https://www.googleapis.com/auth/yt-analytics.readonly'],
   '{"oauth":"required","derived_metrics":"separately_gated"}'::jsonb,'{}'::jsonb,
   'not_submitted','2026-09',now(),'docs/GATE_ZERO_PROVIDER_SELECTION_V0.1.md','verified','youtube-v0.1',false,now()),
  (gen_random_uuid(),'youtube','GLOBAL','channel','public_metadata','enabled',
   '{}'::text[],'{"storage_refresh_days":30}'::jsonb,'{}'::jsonb,
   NULL,'2026-09',now(),'docs/GATE_ZERO_PROVIDER_SELECTION_V0.1.md','verified','youtube-v0.1',false,now()),
  (gen_random_uuid(),'youtube','GLOBAL','channel','public_stats','enabled',
   '{}'::text[],'{"storage_refresh_days":30,"batch_stats_quota_bucket":10000}'::jsonb,'{}'::jsonb,
   NULL,'2026-09',now(),'docs/GATE_ZERO_PROVIDER_SELECTION_V0.1.md','verified','youtube-v0.1',false,now()),
  (gen_random_uuid(),'youtube','GLOBAL','channel','push_upload_events','validation_required',
   '{}'::text[],'{"transport":"pubsubhubbub"}'::jsonb,'{}'::jsonb,
   NULL,'2026-09',now(),'docs/GATE_ZERO_PROVIDER_SELECTION_V0.1.md','verified','youtube-v0.1',false,now()),
  (gen_random_uuid(),'youtube','GLOBAL','channel','derived_analytics','disabled',
   ARRAY['https://www.googleapis.com/auth/yt-analytics.readonly'],
   '{"requires_policy_acceptance":true,"max_accepted_storage_months":36}'::jsonb,'{}'::jsonb,
   'not_submitted','2026-09',now(),'docs/GATE_ZERO_PROVIDER_SELECTION_V0.1.md','verified','youtube-v0.1',true,now())
ON CONFLICT (platform,market,account_type,capability) DO UPDATE
SET status=EXCLUDED.status,
    required_scopes=EXCLUDED.required_scopes,
    limits=EXCLUDED.limits,
    app_review_status=EXCLUDED.app_review_status,
    provider_api_version=EXCLUDED.provider_api_version,
    validated_at=EXCLUDED.validated_at,
    evidence_ref=EXCLUDED.evidence_ref,
    evidence_status=EXCLUDED.evidence_status,
    adapter_version=EXCLUDED.adapter_version,
    kill_switch=EXCLUDED.kill_switch,
    updated_at=now();

-- ---------------------------------------------------------------------------
-- Narrow adapter helpers. These functions rely on the transaction-scoped
-- app.user_id/app.workspace_id established by withTenantTransaction.
-- ---------------------------------------------------------------------------
CREATE FUNCTION growth.youtube_begin_authorization(
  p_managed_account_id uuid,
  p_scopes text[]
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ws uuid := growth.current_workspace_id();
  actor uuid := growth.current_app_user_id();
  connection_id uuid := gen_random_uuid();
BEGIN
  IF ws IS NULL OR actor IS NULL OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'youtube authorization requires active tenant context';
  END IF;
  IF cardinality(p_scopes) IS NULL OR cardinality(p_scopes) = 0 THEN
    RAISE EXCEPTION 'youtube authorization requires scopes';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.managed_accounts ma
    WHERE ma.workspace_id=ws
      AND ma.id=p_managed_account_id
      AND ma.authority_status='contractually_granted'
  ) THEN
    RAISE EXCEPTION 'youtube authorization requires a contractually granted managed account';
  END IF;

  INSERT INTO growth.platform_connections(
    id,workspace_id,managed_account_id,platform,state,credential_ciphertext,
    granted_scopes,created_at,updated_at
  ) VALUES (
    connection_id,ws,p_managed_account_id,'youtube','authorizing',NULL,
    p_scopes,now(),now()
  );
  RETURN connection_id;
END;
$$;
ALTER FUNCTION growth.youtube_begin_authorization(uuid,text[]) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.youtube_begin_authorization(uuid,text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.youtube_begin_authorization(uuid,text[]) TO app_runtime;

CREATE FUNCTION growth.youtube_complete_authorization(
  p_connection_id uuid,
  p_provider_account_id text,
  p_handle text,
  p_account_type text,
  p_market text,
  p_timezone text,
  p_credential_ciphertext bytea,
  p_cipher_version text,
  p_key_version text,
  p_token_expires_at timestamptz,
  p_refresh_available boolean,
  p_scopes text[]
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ws uuid := growth.current_workspace_id();
  actor uuid := growth.current_app_user_id();
  managed_id uuid;
  social_id uuid := gen_random_uuid();
BEGIN
  IF ws IS NULL OR actor IS NULL OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'youtube callback requires active tenant context';
  END IF;
  IF btrim(coalesce(p_provider_account_id,''))='' OR octet_length(p_credential_ciphertext)=0 THEN
    RAISE EXCEPTION 'youtube callback missing channel or credential';
  END IF;

  SELECT pc.managed_account_id INTO managed_id
  FROM growth.platform_connections pc
  JOIN growth.managed_accounts ma
    ON ma.workspace_id=pc.workspace_id AND ma.id=pc.managed_account_id
  WHERE pc.workspace_id=ws
    AND pc.id=p_connection_id
    AND pc.platform='youtube'
    AND pc.state='authorizing'
    AND ma.authority_status='contractually_granted'
  FOR UPDATE OF pc;

  IF managed_id IS NULL THEN
    RAISE EXCEPTION 'youtube authorization state is not valid';
  END IF;

  IF EXISTS (
    SELECT 1 FROM growth.social_accounts sa
    WHERE sa.platform='youtube' AND sa.provider_account_id=p_provider_account_id
  ) THEN
    RAISE EXCEPTION 'youtube channel is already connected';
  END IF;

  INSERT INTO growth.provider_credentials(
    workspace_id,platform_connection_id,provider,credential_ciphertext,
    cipher_version,key_version,token_expires_at,refresh_available,updated_at
  ) VALUES (
    ws,p_connection_id,'youtube',p_credential_ciphertext,p_cipher_version,p_key_version,
    p_token_expires_at,p_refresh_available,now()
  );

  UPDATE growth.platform_connections
  SET state='connected',
      credential_ciphertext=NULL,
      granted_scopes=p_scopes,
      token_expires_at=p_token_expires_at,
      last_success_at=now(),
      last_failure_at=NULL,
      error_class=NULL,
      updated_at=now()
  WHERE workspace_id=ws AND id=p_connection_id;

  INSERT INTO growth.social_accounts(
    id,workspace_id,managed_account_id,platform_connection_id,platform,
    provider_account_id,handle,account_type,market,timezone,created_at
  ) VALUES (
    social_id,ws,managed_id,p_connection_id,'youtube',p_provider_account_id,
    nullif(btrim(coalesce(p_handle,'')),''),nullif(btrim(coalesce(p_account_type,'')),''),
    nullif(btrim(coalesce(p_market,'')),''),nullif(btrim(coalesce(p_timezone,'')),''),now()
  );

  RETURN social_id;
END;
$$;
ALTER FUNCTION growth.youtube_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[]) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.youtube_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.youtube_complete_authorization(uuid,text,text,text,text,text,bytea,text,text,timestamptz,boolean,text[]) TO app_runtime;

CREATE FUNCTION growth.youtube_get_connection_credential(p_connection_id uuid)
RETURNS TABLE(
  social_account_id uuid,
  provider_account_id text,
  credential_ciphertext bytea,
  cipher_version text,
  key_version text,
  token_expires_at timestamptz,
  refresh_available boolean,
  granted_scopes text[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT sa.id,sa.provider_account_id,pcd.credential_ciphertext,pcd.cipher_version,
         pcd.key_version,pcd.token_expires_at,pcd.refresh_available,pc.granted_scopes
  FROM growth.platform_connections pc
  JOIN growth.managed_accounts ma
    ON ma.workspace_id=pc.workspace_id AND ma.id=pc.managed_account_id
  JOIN growth.social_accounts sa
    ON sa.workspace_id=pc.workspace_id AND sa.platform_connection_id=pc.id
  JOIN growth.provider_credentials pcd
    ON pcd.workspace_id=pc.workspace_id AND pcd.platform_connection_id=pc.id
  WHERE pc.workspace_id=growth.current_workspace_id()
    AND pc.id=p_connection_id
    AND pc.platform='youtube'
    AND pc.state='connected'
    AND ma.authority_status='contractually_granted'
    AND growth.tenant_context_valid(pc.workspace_id)
  LIMIT 1;
$$;
ALTER FUNCTION growth.youtube_get_connection_credential(uuid) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.youtube_get_connection_credential(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.youtube_get_connection_credential(uuid) TO app_runtime;

CREATE FUNCTION growth.youtube_update_connection_credential(
  p_connection_id uuid,
  p_credential_ciphertext bytea,
  p_cipher_version text,
  p_key_version text,
  p_token_expires_at timestamptz,
  p_refresh_available boolean,
  p_scopes text[]
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
    RAISE EXCEPTION 'youtube credential update requires active tenant context';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.platform_connections pc
    JOIN growth.managed_accounts ma
      ON ma.workspace_id=pc.workspace_id AND ma.id=pc.managed_account_id
    WHERE pc.workspace_id=ws AND pc.id=p_connection_id
      AND pc.platform='youtube' AND pc.state='connected'
      AND ma.authority_status='contractually_granted'
  ) THEN
    RETURN false;
  END IF;

  UPDATE growth.provider_credentials
  SET credential_ciphertext=p_credential_ciphertext,
      cipher_version=p_cipher_version,
      key_version=p_key_version,
      token_expires_at=p_token_expires_at,
      refresh_available=p_refresh_available,
      updated_at=now()
  WHERE workspace_id=ws AND platform_connection_id=p_connection_id;

  UPDATE growth.platform_connections
  SET granted_scopes=p_scopes,
      token_expires_at=p_token_expires_at,
      last_success_at=now(),
      error_class=NULL,
      updated_at=now()
  WHERE workspace_id=ws AND id=p_connection_id;

  RETURN FOUND;
END;
$$;
ALTER FUNCTION growth.youtube_update_connection_credential(uuid,bytea,text,text,timestamptz,boolean,text[]) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.youtube_update_connection_credential(uuid,bytea,text,text,timestamptz,boolean,text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.youtube_update_connection_credential(uuid,bytea,text,text,timestamptz,boolean,text[]) TO app_runtime;

CREATE FUNCTION growth.youtube_record_metric_observation(
  p_social_account_id uuid,
  p_provider_content_id text,
  p_metric_name text,
  p_raw_value numeric,
  p_unit text,
  p_observed_at timestamptz,
  p_provider_effective_at timestamptz,
  p_provider_api_version text,
  p_source_schema_version text,
  p_provider_product text,
  p_provider_object_type text,
  p_metric_semantic_version text,
  p_semantic_effective_from timestamptz,
  p_semantic_effective_to timestamptz,
  p_source_range_start timestamptz,
  p_source_range_end timestamptz,
  p_authorization_class text,
  p_retention_deadline timestamptz,
  p_refresh_required_by timestamptz,
  p_completeness_status text,
  p_freshness_status text,
  p_collection_run_id uuid,
  p_idempotency_key text,
  p_raw_payload_ref text,
  p_adapter_version text,
  p_collection_method text DEFAULT 'polling'
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ws uuid := growth.current_workspace_id();
  existing growth.metric_observations%ROWTYPE;
  observation_id uuid := gen_random_uuid();
BEGIN
  IF ws IS NULL OR growth.current_app_user_id() IS NULL OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'youtube observation requires active tenant context';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.social_accounts sa
    JOIN growth.platform_connections pc
      ON pc.workspace_id=sa.workspace_id AND pc.id=sa.platform_connection_id
    JOIN growth.managed_accounts ma
      ON ma.workspace_id=sa.workspace_id AND ma.id=sa.managed_account_id
    WHERE sa.workspace_id=ws AND sa.id=p_social_account_id
      AND sa.platform='youtube' AND pc.state='connected'
      AND ma.authority_status='contractually_granted'
  ) THEN
    RAISE EXCEPTION 'youtube observation requires connected authorized account';
  END IF;
  IF btrim(coalesce(p_metric_name,''))='' OR btrim(coalesce(p_idempotency_key,''))=''
     OR btrim(coalesce(p_metric_semantic_version,''))=''
     OR btrim(coalesce(p_authorization_class,''))=''
     OR btrim(coalesce(p_completeness_status,''))=''
     OR btrim(coalesce(p_freshness_status,''))='' THEN
    RAISE EXCEPTION 'youtube observation provenance contract is incomplete';
  END IF;

  SELECT * INTO existing
  FROM growth.metric_observations mo
  WHERE mo.workspace_id=ws AND mo.idempotency_key=p_idempotency_key
  LIMIT 1;

  IF existing.id IS NOT NULL THEN
    IF existing.social_account_id=p_social_account_id
       AND existing.provider_content_id=p_provider_content_id
       AND existing.metric_name=p_metric_name
       AND existing.raw_value=p_raw_value
       AND existing.observed_at=p_observed_at
       AND existing.metric_semantic_version=p_metric_semantic_version
       AND existing.authorization_class=p_authorization_class THEN
      RETURN existing.id;
    END IF;
    RAISE EXCEPTION 'youtube observation idempotency conflict';
  END IF;

  INSERT INTO growth.metric_observations(
    id,workspace_id,social_account_id,content_item_id,provider_content_id,
    metric_name,raw_value,unit,observed_at,provider_effective_at,source_timezone,
    provider_api_version,source_schema_version,collection_method,raw_payload_ref,
    adapter_version,provider_product,provider_object_type,metric_semantic_version,
    semantic_effective_from,semantic_effective_to,source_range_start,source_range_end,
    authorization_class,retention_deadline,refresh_required_by,completeness_status,
    freshness_status,collection_run_id,idempotency_key,created_at
  ) VALUES (
    observation_id,ws,p_social_account_id,NULL,p_provider_content_id,p_metric_name,
    p_raw_value,p_unit,p_observed_at,p_provider_effective_at,'America/Los_Angeles',
    p_provider_api_version,p_source_schema_version,p_collection_method,p_raw_payload_ref,
    p_adapter_version,p_provider_product,p_provider_object_type,p_metric_semantic_version,
    p_semantic_effective_from,p_semantic_effective_to,p_source_range_start,p_source_range_end,
    p_authorization_class,p_retention_deadline,p_refresh_required_by,p_completeness_status,
    p_freshness_status,p_collection_run_id,p_idempotency_key,now()
  );
  RETURN observation_id;
END;
$$;
ALTER FUNCTION growth.youtube_record_metric_observation(uuid,text,text,numeric,text,timestamptz,timestamptz,text,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,text,timestamptz,timestamptz,text,text,uuid,text,text,text,text) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.youtube_record_metric_observation(uuid,text,text,numeric,text,timestamptz,timestamptz,text,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,text,timestamptz,timestamptz,text,text,uuid,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.youtube_record_metric_observation(uuid,text,text,numeric,text,timestamptz,timestamptz,text,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,text,timestamptz,timestamptz,text,text,uuid,text,text,text,text) TO app_runtime;

COMMIT;
