-- Growth OS — Instagram media and metric ingestion foundation.
-- Forward-only migration. Adds provider media storage and narrow write helpers.
-- app_runtime receives EXECUTE only; table access remains denied.

\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

CREATE TABLE growth.instagram_media (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  social_account_id uuid NOT NULL,
  provider_media_id text NOT NULL,
  media_type text NOT NULL,
  media_product_type text,
  permalink text,
  caption text,
  posted_at timestamptz,
  media_url text,
  thumbnail_url text,
  collected_at timestamptz NOT NULL,
  raw_payload_ref text NOT NULL,
  adapter_version text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, provider_media_id),
  FOREIGN KEY (workspace_id, social_account_id)
    REFERENCES growth.social_accounts(workspace_id, id),
  CHECK (btrim(provider_media_id) <> ''),
  CHECK (btrim(media_type) <> ''),
  CHECK (btrim(raw_payload_ref) <> ''),
  CHECK (btrim(adapter_version) <> '')
);

ALTER TABLE growth.instagram_media OWNER TO growth_migrator;
ALTER TABLE growth.instagram_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.instagram_media FORCE ROW LEVEL SECURITY;

CREATE POLICY instagram_media_workspace_isolation
  ON growth.instagram_media
  USING (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
  )
  WITH CHECK (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
  );

REVOKE ALL ON TABLE growth.instagram_media FROM PUBLIC;
REVOKE ALL ON TABLE growth.instagram_media FROM app_runtime;

CREATE INDEX instagram_media_account_posted_idx
  ON growth.instagram_media(workspace_id, social_account_id, posted_at DESC);

CREATE FUNCTION growth.instagram_record_media(
  p_social_account_id uuid,
  p_provider_media_id text,
  p_media_type text,
  p_media_product_type text,
  p_permalink text,
  p_caption text,
  p_posted_at timestamptz,
  p_media_url text,
  p_thumbnail_url text,
  p_collected_at timestamptz,
  p_raw_payload_ref text,
  p_adapter_version text
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ws uuid := growth.current_workspace_id();
  existing_id uuid;
  existing_account uuid;
  media_id uuid := gen_random_uuid();
BEGIN
  IF ws IS NULL OR growth.current_app_user_id() IS NULL OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'instagram media requires active tenant context';
  END IF;
  IF btrim(coalesce(p_provider_media_id,'')) = ''
     OR btrim(coalesce(p_media_type,'')) = ''
     OR btrim(coalesce(p_raw_payload_ref,'')) = ''
     OR btrim(coalesce(p_adapter_version,'')) = ''
     OR p_collected_at IS NULL THEN
    RAISE EXCEPTION 'instagram media provenance contract is incomplete';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM growth.social_accounts sa
    JOIN growth.platform_connections pc
      ON pc.workspace_id=sa.workspace_id AND pc.id=sa.platform_connection_id
    JOIN growth.managed_accounts ma
      ON ma.workspace_id=sa.workspace_id AND ma.id=sa.managed_account_id
    WHERE sa.workspace_id=ws
      AND sa.id=p_social_account_id
      AND sa.platform='instagram'
      AND pc.platform='instagram'
      AND pc.state='connected'
      AND ma.authority_status='contractually_granted'
  ) THEN
    RAISE EXCEPTION 'instagram media requires connected authorized account';
  END IF;

  SELECT im.id, im.social_account_id
    INTO existing_id, existing_account
  FROM growth.instagram_media im
  WHERE im.workspace_id=ws
    AND im.provider_media_id=p_provider_media_id
  FOR UPDATE;

  IF existing_id IS NOT NULL AND existing_account <> p_social_account_id THEN
    RAISE EXCEPTION 'instagram media belongs to another social account';
  END IF;

  IF existing_id IS NULL THEN
    INSERT INTO growth.instagram_media(
      id,workspace_id,social_account_id,provider_media_id,media_type,
      media_product_type,permalink,caption,posted_at,media_url,thumbnail_url,
      collected_at,raw_payload_ref,adapter_version,created_at,updated_at
    )
    VALUES(
      media_id,ws,p_social_account_id,p_provider_media_id,p_media_type,
      nullif(btrim(coalesce(p_media_product_type,'')),''),
      nullif(btrim(coalesce(p_permalink,'')),''),
      p_caption,p_posted_at,p_media_url,p_thumbnail_url,
      p_collected_at,p_raw_payload_ref,p_adapter_version,now(),now()
    );
    RETURN media_id;
  END IF;

  UPDATE growth.instagram_media
  SET media_type=p_media_type,
      media_product_type=nullif(btrim(coalesce(p_media_product_type,'')),''),
      permalink=nullif(btrim(coalesce(p_permalink,'')),''),
      caption=p_caption,
      posted_at=p_posted_at,
      media_url=p_media_url,
      thumbnail_url=p_thumbnail_url,
      collected_at=p_collected_at,
      raw_payload_ref=p_raw_payload_ref,
      adapter_version=p_adapter_version,
      updated_at=now()
  WHERE workspace_id=ws AND id=existing_id;

  RETURN existing_id;
END;
$$;

ALTER FUNCTION growth.instagram_record_media(uuid,text,text,text,text,text,timestamptz,text,text,timestamptz,text,text) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.instagram_record_media(uuid,text,text,text,text,text,timestamptz,text,text,timestamptz,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_record_media(uuid,text,text,text,text,text,timestamptz,text,text,timestamptz,text,text) TO app_runtime;

CREATE FUNCTION growth.instagram_record_metric_observation(
  p_social_account_id uuid,
  p_provider_content_id text,
  p_metric_name text,
  p_raw_value numeric,
  p_unit text,
  p_observed_at timestamptz,
  p_provider_effective_at timestamptz,
  p_source_timezone text,
  p_provider_api_version text,
  p_source_schema_version text,
  p_provider_product text,
  p_provider_object_type text,
  p_metric_semantic_version text,
  p_semantic_effective_from timestamptz,
  p_semantic_effective_to timestamptz,
  p_source_range_start timestamptz,
  p_source_range_end timestamptz,
  p_collected_at timestamptz,
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
    RAISE EXCEPTION 'instagram observation requires active tenant context';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM growth.social_accounts sa
    JOIN growth.platform_connections pc
      ON pc.workspace_id=sa.workspace_id AND pc.id=sa.platform_connection_id
    JOIN growth.managed_accounts ma
      ON ma.workspace_id=sa.workspace_id AND ma.id=sa.managed_account_id
    WHERE sa.workspace_id=ws
      AND sa.id=p_social_account_id
      AND sa.platform='instagram'
      AND pc.platform='instagram'
      AND pc.state='connected'
      AND ma.authority_status='contractually_granted'
  ) THEN
    RAISE EXCEPTION 'instagram observation requires connected authorized account';
  END IF;
  IF btrim(coalesce(p_provider_content_id,''))=''
     OR btrim(coalesce(p_metric_name,''))=''
     OR btrim(coalesce(p_idempotency_key,''))=''
     OR btrim(coalesce(p_metric_semantic_version,''))=''
     OR p_collected_at IS NULL
     OR btrim(coalesce(p_authorization_class,''))=''
     OR btrim(coalesce(p_completeness_status,''))=''
     OR btrim(coalesce(p_freshness_status,''))=''
     OR btrim(coalesce(p_adapter_version,''))='' THEN
    RAISE EXCEPTION 'instagram observation provenance contract is incomplete';
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
    RAISE EXCEPTION 'instagram observation idempotency conflict';
  END IF;

  INSERT INTO growth.metric_observations(
    id,workspace_id,social_account_id,content_item_id,provider_content_id,
    metric_name,raw_value,unit,observed_at,provider_effective_at,source_timezone,
    provider_api_version,source_schema_version,collection_method,raw_payload_ref,
    adapter_version,provider_product,provider_object_type,metric_semantic_version,
    semantic_effective_from,semantic_effective_to,source_range_start,source_range_end,
    collected_at,authorization_class,retention_deadline,refresh_required_by,
    completeness_status,freshness_status,collection_run_id,idempotency_key,created_at
  ) VALUES (
    observation_id,ws,p_social_account_id,NULL,p_provider_content_id,
    p_metric_name,p_raw_value,p_unit,p_observed_at,p_provider_effective_at,
    p_source_timezone,p_provider_api_version,p_source_schema_version,
    p_collection_method,p_raw_payload_ref,p_adapter_version,p_provider_product,
    p_provider_object_type,p_metric_semantic_version,p_semantic_effective_from,
    p_semantic_effective_to,p_source_range_start,p_source_range_end,p_collected_at,
    p_authorization_class,p_retention_deadline,p_refresh_required_by,
    p_completeness_status,p_freshness_status,p_collection_run_id,p_idempotency_key,now()
  );
  RETURN observation_id;
END;
$$;

ALTER FUNCTION growth.instagram_record_metric_observation(uuid,text,text,numeric,text,timestamptz,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,text,timestamptz,timestamptz,text,text,uuid,text,text,text,text) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.instagram_record_metric_observation(uuid,text,text,numeric,text,timestamptz,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,text,text,timestamptz,timestamptz,text,text,uuid,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_record_metric_observation(uuid,text,text,numeric,text,timestamptz,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,text,timestamptz,timestamptz,text,text,uuid,text,text,text,text) TO app_runtime;

COMMIT;
