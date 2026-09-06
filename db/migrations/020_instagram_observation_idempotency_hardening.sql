-- Growth OS — forward-only hardening of Instagram observation idempotency.
-- Migration 019 remains immutable after validation. This replacement mirrors the
-- proven YouTube 013 contract: one idempotency key cannot alias materially
-- different factual or provenance fields.

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  fn regprocedure := 'growth.instagram_record_metric_observation(uuid,text,text,numeric,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,timestamp with time zone,text,text,uuid,text,text,text,text)'::regprocedure;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid=fn
      AND pg_get_userbyid(p.proowner)='growth_migrator'
      AND p.prosecdef
  ) THEN
    RAISE EXCEPTION '020 failed: instagram_record_metric_observation ownership/security boundary changed';
  END IF;

  IF has_function_privilege('public',fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '020 failed: PUBLIC unexpectedly has EXECUTE on instagram_record_metric_observation';
  END IF;

  IF NOT has_function_privilege('app_runtime',fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '020 failed: app_runtime lacks required helper EXECUTE';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION growth.instagram_record_metric_observation(
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
    -- collected_at / retention_deadline / refresh_required_by are intentionally excluded:
    -- those are retry-time policy metadata. Everything below is stable factual/source
    -- identity for one logical collection run and must remain identical under one key.
    IF ROW(
         existing.social_account_id,
         existing.provider_content_id,
         existing.metric_name,
         existing.raw_value,
         existing.unit,
         existing.observed_at,
         existing.provider_effective_at,
         existing.provider_api_version,
         existing.source_schema_version,
         existing.collection_method,
         existing.raw_payload_ref,
         existing.adapter_version,
         existing.provider_product,
         existing.provider_object_type,
         existing.metric_semantic_version,
         existing.semantic_effective_from,
         existing.semantic_effective_to,
         existing.source_range_start,
         existing.source_range_end,
         existing.authorization_class,
         existing.completeness_status,
         existing.freshness_status,
         existing.collection_run_id
       ) IS NOT DISTINCT FROM ROW(
         p_social_account_id,
         p_provider_content_id,
         p_metric_name,
         p_raw_value,
         p_unit,
         p_observed_at,
         p_provider_effective_at,
         p_provider_api_version,
         p_source_schema_version,
         p_collection_method,
         p_raw_payload_ref,
         p_adapter_version,
         p_provider_product,
         p_provider_object_type,
         p_metric_semantic_version,
         p_semantic_effective_from,
         p_semantic_effective_to,
         p_source_range_start,
         p_source_range_end,
         p_authorization_class,
         p_completeness_status,
         p_freshness_status,
         p_collection_run_id
       ) THEN
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
REVOKE ALL ON FUNCTION growth.instagram_record_metric_observation(uuid,text,text,numeric,text,timestamptz,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,text,timestamptz,timestamptz,text,text,uuid,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_record_metric_observation(uuid,text,text,numeric,text,timestamptz,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,text,timestamptz,timestamptz,text,text,uuid,text,text,text,text) TO app_runtime;

COMMIT;
