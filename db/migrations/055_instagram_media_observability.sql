-- Growth OS — per-media Instagram observability.
-- Exposes only tenant-scoped, provider-identified media and metric history.

BEGIN;
SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.list_instagram_media(
  p_connection_id uuid,
  p_lookback_days integer DEFAULT 7,
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  media_id uuid,
  provider_media_id text,
  media_type text,
  media_product_type text,
  permalink text,
  caption text,
  posted_at timestamptz,
  media_url text,
  thumbnail_url text,
  first_seen_at timestamptz,
  last_synced_at timestamptz,
  latest_like_count numeric,
  latest_comments_count numeric,
  latest_metric_count integer,
  observation_count bigint,
  first_observed_at timestamptz,
  last_observed_at timestamptz,
  metric_history jsonb,
  opportunity_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ws uuid := growth.current_workspace_id();
  social_id uuid;
  observability_version constant text := 'instagram.media.observability.v2';
BEGIN
  IF ws IS NULL
     OR growth.current_app_user_id() IS NULL
     OR NOT growth.tenant_context_valid(ws)
  THEN
    RAISE EXCEPTION 'instagram media listing requires active tenant context';
  END IF;

  IF p_lookback_days IS NULL OR p_lookback_days < 1 OR p_lookback_days > 366 THEN
    RAISE EXCEPTION 'instagram media lookback must be between 1 and 366 days';
  END IF;

  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'instagram media limit must be between 1 and 100';
  END IF;

  SELECT sa.id
    INTO social_id
    FROM growth.platform_connections pc
    JOIN growth.social_accounts sa
      ON sa.workspace_id = pc.workspace_id
     AND sa.platform_connection_id = pc.id
     AND sa.platform = 'instagram'
    JOIN growth.managed_accounts ma
      ON ma.workspace_id = pc.workspace_id
     AND ma.id = pc.managed_account_id
   WHERE pc.workspace_id = ws
     AND pc.id = p_connection_id
     AND pc.platform = 'instagram'
     AND pc.state = 'connected'
     AND ma.authority_status = 'contractually_granted';

  IF social_id IS NULL THEN
    RAISE EXCEPTION 'instagram media listing requires connected authorized account';
  END IF;

  RETURN QUERY
  WITH media_scope AS (
    SELECT im.id,
           im.provider_media_id,
           im.media_type,
           im.media_product_type,
           im.permalink,
           im.caption,
           im.posted_at,
           im.media_url,
           im.thumbnail_url,
           im.created_at,
           im.collected_at,
           im.updated_at
      FROM growth.instagram_media im
     WHERE im.workspace_id = ws
       AND im.social_account_id = social_id
       AND im.posted_at >= now() - make_interval(days => p_lookback_days)
     ORDER BY im.posted_at DESC NULLS LAST, im.updated_at DESC, im.id
     LIMIT p_limit
  ),
  metric_ranked AS (
    SELECT mo.id,
           mo.provider_content_id,
           mo.metric_name,
           mo.raw_value,
           mo.observed_at,
           row_number() OVER (
             PARTITION BY mo.provider_content_id, mo.metric_name
             ORDER BY mo.observed_at DESC, mo.id DESC
           ) AS metric_rank,
           row_number() OVER (
             PARTITION BY mo.provider_content_id
             ORDER BY mo.observed_at DESC, mo.id DESC
           ) AS history_rank
      FROM growth.metric_observations mo
      JOIN media_scope ms
        ON ms.provider_media_id = mo.provider_content_id
     WHERE mo.workspace_id = ws
       AND mo.social_account_id = social_id
  ),
  metric_summary AS (
    SELECT provider_content_id,
           max(raw_value) FILTER (WHERE metric_name = 'like_count' AND metric_rank = 1) AS latest_like_count,
           max(raw_value) FILTER (WHERE metric_name = 'comments_count' AND metric_rank = 1) AS latest_comments_count,
           count(*) FILTER (WHERE metric_rank = 1)::integer AS latest_metric_count,
           count(*)::bigint AS observation_count,
           min(observed_at) AS first_observed_at,
           max(observed_at) AS last_observed_at
      FROM metric_ranked
     GROUP BY provider_content_id
  ),
  metric_history AS (
    SELECT provider_content_id,
           jsonb_agg(
             jsonb_build_object(
               'metric_name', metric_name,
               'value', raw_value,
               'observed_at', observed_at
             ) ORDER BY observed_at DESC, id DESC
           ) AS history
      FROM metric_ranked
     WHERE history_rank <= 20
     GROUP BY provider_content_id
  ),
  linked_opportunities AS (
    SELECT mo.provider_content_id,
           count(DISTINCT oe.opportunity_id)::bigint AS opportunity_count
      FROM growth.metric_observations mo
      JOIN growth.opportunity_evidence oe
        ON oe.workspace_id = mo.workspace_id
       AND oe.evidence_ref = 'metric_observation:' || mo.id::text
      JOIN growth.opportunities o
        ON o.workspace_id = oe.workspace_id
       AND o.id = oe.opportunity_id
     WHERE mo.workspace_id = ws
       AND mo.social_account_id = social_id
       AND (o.expires_at IS NULL OR o.expires_at > now())
     GROUP BY mo.provider_content_id
  )
  SELECT ms.id,
         ms.provider_media_id,
         ms.media_type,
         ms.media_product_type,
         ms.permalink,
         ms.caption,
         ms.posted_at,
         ms.media_url,
         ms.thumbnail_url,
         ms.created_at,
         ms.collected_at,
         summary.latest_like_count,
         summary.latest_comments_count,
         coalesce(summary.latest_metric_count, 0),
         coalesce(summary.observation_count, 0),
         summary.first_observed_at,
         summary.last_observed_at,
         coalesce(history.history, '[]'::jsonb),
         coalesce(linked.opportunity_count, 0)
    FROM media_scope ms
    LEFT JOIN metric_summary summary
      ON summary.provider_content_id = ms.provider_media_id
    LEFT JOIN metric_history history
      ON history.provider_content_id = ms.provider_media_id
    LEFT JOIN linked_opportunities linked
      ON linked.provider_content_id = ms.provider_media_id
   ORDER BY ms.posted_at DESC NULLS LAST, ms.updated_at DESC, ms.id;
END;
$$;

ALTER FUNCTION growth.list_instagram_media(uuid,integer,integer) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.list_instagram_media(uuid,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.list_instagram_media(uuid,integer,integer) TO app_runtime;

COMMIT;
