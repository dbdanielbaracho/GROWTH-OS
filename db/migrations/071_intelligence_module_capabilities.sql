-- Growth OS — evidence-bounded intelligence module capability contract.
-- Forward-only migration 071. Provider capability rows describe what the
-- current adapters may truthfully claim; they do not manufacture intelligence.

BEGIN;
SET search_path = growth, public;

INSERT INTO growth.capabilities(
  id, platform, market, account_type, capability, status, required_scopes,
  limits, media_constraints, app_review_status, provider_api_version,
  validated_at, evidence_ref, evidence_status, adapter_version, kill_switch, updated_at
)
VALUES
  (gen_random_uuid(),'instagram','GLOBAL','professional','intelligence_global_trend_migration','validation_required',
   ARRAY['instagram_business_basic'],
   '{"reason":"external cross-market discovery is not implemented in the current Instagram Login adapter"}'::jsonb,
   '{}'::jsonb,'not_submitted','instagram-api-with-instagram-login','2026-09-19T00:00:00Z',
   'https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api','verified','intelligence-v0.1',true,now()),
  (gen_random_uuid(),'instagram','GLOBAL','professional','intelligence_competitor_intelligence','validation_required',
   ARRAY['instagram_business_basic'],
   '{"reason":"competitor evidence requires an explicitly reviewed provider-permitted discovery path"}'::jsonb,
   '{}'::jsonb,'not_submitted','instagram-api-with-instagram-login','2026-09-19T00:00:00Z',
   'https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api','verified','intelligence-v0.1',true,now()),
  (gen_random_uuid(),'instagram','GLOBAL','professional','intelligence_viral_dna','validation_required',
   ARRAY['instagram_business_basic','instagram_business_manage_insights'],
   '{"reason":"module can use stored owned evidence but provider analytics remain permission/app-review bounded"}'::jsonb,
   '{}'::jsonb,'not_submitted','instagram-api-with-instagram-login','2026-09-19T00:00:00Z',
   'https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api','verified','intelligence-v0.1',true,now()),

  (gen_random_uuid(),'youtube','GLOBAL','channel','intelligence_global_trend_migration','validation_required',
   '{}'::text[],
   '{"reason":"public metadata/stats exist, but cross-target trend discovery and ingestion are not implemented"}'::jsonb,
   '{}'::jsonb,NULL,'2026-09','2026-09-19T00:00:00Z',
   'https://developers.google.com/youtube/v3/docs/channels','verified','intelligence-v0.1',true,now()),
  (gen_random_uuid(),'youtube','GLOBAL','channel','intelligence_competitor_intelligence','validation_required',
   '{}'::text[],
   '{"reason":"public channel stats exist, but arbitrary competitor target ingestion is not implemented"}'::jsonb,
   '{}'::jsonb,NULL,'2026-09','2026-09-19T00:00:00Z',
   'https://developers.google.com/youtube/v3/docs/channels','verified','intelligence-v0.1',true,now()),
  (gen_random_uuid(),'youtube','GLOBAL','channel','intelligence_viral_dna','validation_required',
   ARRAY['https://www.googleapis.com/auth/yt-analytics.readonly'],
   '{"reason":"owned measured learning is supported only after authorized analytics are available"}'::jsonb,
   '{}'::jsonb,'not_submitted','2026-09','2026-09-19T00:00:00Z',
   'https://developers.google.com/youtube/analytics','verified','intelligence-v0.1',true,now()),

  (gen_random_uuid(),'tiktok','GLOBAL','commercial','intelligence_global_trend_migration','disabled',
   '{}'::text[],
   '{"reason":"TikTok Research Tools are not available to creators, advertisers, or commercial users"}'::jsonb,
   '{}'::jsonb,NULL,'research-api-2026-09','2026-09-19T00:00:00Z',
   'https://developers.tiktok.com/doc/research-api-faq','verified','intelligence-v0.1',true,now()),
  (gen_random_uuid(),'tiktok','GLOBAL','commercial','intelligence_competitor_intelligence','disabled',
   '{}'::text[],
   '{"reason":"no approved commercial competitor-research connector is configured"}'::jsonb,
   '{}'::jsonb,NULL,'research-api-2026-09','2026-09-19T00:00:00Z',
   'https://developers.tiktok.com/doc/research-api-faq','verified','intelligence-v0.1',true,now()),
  (gen_random_uuid(),'tiktok','GLOBAL','commercial','intelligence_viral_dna','disabled',
   '{}'::text[],
   '{"reason":"no approved commercial research connector is configured"}'::jsonb,
   '{}'::jsonb,NULL,'research-api-2026-09','2026-09-19T00:00:00Z',
   'https://developers.tiktok.com/doc/research-api-faq','verified','intelligence-v0.1',true,now())
ON CONFLICT (platform,market,account_type,capability) DO UPDATE
SET status = EXCLUDED.status,
    required_scopes = EXCLUDED.required_scopes,
    limits = EXCLUDED.limits,
    media_constraints = EXCLUDED.media_constraints,
    app_review_status = EXCLUDED.app_review_status,
    provider_api_version = EXCLUDED.provider_api_version,
    validated_at = EXCLUDED.validated_at,
    evidence_ref = EXCLUDED.evidence_ref,
    evidence_status = EXCLUDED.evidence_status,
    adapter_version = EXCLUDED.adapter_version,
    kill_switch = EXCLUDED.kill_switch,
    updated_at = now();

CREATE OR REPLACE FUNCTION growth.list_intelligence_module_capabilities(p_workspace_id uuid)
RETURNS TABLE(
  module_key text,
  platform text,
  status text,
  evidence_ref text,
  evidence_status text,
  kill_switch boolean,
  limits jsonb
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id) THEN
    RAISE EXCEPTION 'intelligence capability workspace context mismatch';
  END IF;

  RETURN QUERY
  SELECT replace(c.capability, 'intelligence_', '') AS module_key,
         c.platform, c.status, c.evidence_ref, c.evidence_status, c.kill_switch, c.limits
    FROM growth.capabilities c
   WHERE c.capability IN (
     'intelligence_global_trend_migration',
     'intelligence_competitor_intelligence',
     'intelligence_viral_dna'
   )
   ORDER BY c.capability, c.platform;
END;
$$;

CREATE OR REPLACE FUNCTION growth.list_competitor_intelligence_evidence(
  p_workspace_id uuid,
  p_limit integer DEFAULT 100
)
RETURNS TABLE(
  insight_id uuid,
  social_account_id uuid,
  claim text,
  evidence_type text,
  evidence_ref text,
  source_class text,
  created_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id) THEN
    RAISE EXCEPTION 'competitor intelligence workspace context mismatch';
  END IF;

  RETURN QUERY
  SELECT i.id, i.social_account_id, i.claim, ie.evidence_type, ie.evidence_ref,
         ie.source_class, ie.created_at
    FROM growth.insights i
    JOIN growth.insight_evidence ie
      ON ie.workspace_id = i.workspace_id AND ie.insight_id = i.id
   WHERE i.workspace_id = p_workspace_id
     AND i.valid_from <= now()
     AND (i.expires_at IS NULL OR i.expires_at > now())
     AND lower(ie.evidence_type) IN (
       'competitor_metric', 'competitor_observation', 'business_discovery', 'public_channel_stats'
     )
   ORDER BY ie.created_at DESC, ie.id
   LIMIT greatest(1, least(coalesce(p_limit,100),100));
END;
$$;

CREATE OR REPLACE FUNCTION growth.list_viral_dna_evidence(
  p_workspace_id uuid,
  p_limit integer DEFAULT 100
)
RETURNS TABLE(
  insight_id uuid,
  social_account_id uuid,
  claim text,
  evidence_type text,
  evidence_ref text,
  source_class text,
  created_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id) THEN
    RAISE EXCEPTION 'viral DNA workspace context mismatch';
  END IF;

  RETURN QUERY
  SELECT i.id, i.social_account_id, i.claim, ie.evidence_type, ie.evidence_ref,
         ie.source_class, ie.created_at
    FROM growth.insights i
    JOIN growth.insight_evidence ie
      ON ie.workspace_id = i.workspace_id AND ie.insight_id = i.id
   WHERE i.workspace_id = p_workspace_id
     AND i.state = 'confirmed_account'
     AND i.valid_from <= now()
     AND (i.expires_at IS NULL OR i.expires_at > now())
   ORDER BY ie.weight DESC NULLS LAST, ie.created_at DESC, ie.id
   LIMIT greatest(1, least(coalesce(p_limit,100),100));
END;
$$;

ALTER FUNCTION growth.list_intelligence_module_capabilities(uuid) OWNER TO growth_migrator;
ALTER FUNCTION growth.list_competitor_intelligence_evidence(uuid,integer) OWNER TO growth_migrator;
ALTER FUNCTION growth.list_viral_dna_evidence(uuid,integer) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.list_intelligence_module_capabilities(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.list_competitor_intelligence_evidence(uuid,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.list_viral_dna_evidence(uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.list_intelligence_module_capabilities(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.list_competitor_intelligence_evidence(uuid,integer) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.list_viral_dna_evidence(uuid,integer) TO app_runtime;

COMMIT;
