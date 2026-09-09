-- Deterministic data-quality anomalies over real provider observations.
-- This projection never synthesizes metric values or statistical outliers.
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION growth.list_metric_quality_anomalies(
  p_workspace_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS TABLE (
  social_account_id uuid,
  platform text,
  provider_account_id text,
  handle text,
  metric_name text,
  observation_count bigint,
  latest_observed_at timestamptz,
  latest_effective_at timestamptz,
  complete_observations bigint,
  fresh_observations bigint,
  quality_status text,
  anomaly_reason text,
  completeness_ratio numeric,
  freshness_ratio numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'metric quality workspace context mismatch';
  END IF;

  IF p_from IS NULL OR p_to IS NULL OR p_to <= p_from THEN
    RAISE EXCEPTION 'metric quality window must be positive';
  END IF;

  IF p_to - p_from > interval '366 days' THEN
    RAISE EXCEPTION 'metric quality window exceeds maximum range';
  END IF;

  RETURN QUERY
  WITH grouped AS (
    SELECT
      sa.id AS social_account_id,
      sa.platform,
      sa.provider_account_id,
      sa.handle,
      mo.metric_name,
      count(*)::bigint AS observation_count,
      max(mo.observed_at) AS latest_observed_at,
      max(coalesce(mo.provider_effective_at, mo.observed_at)) AS latest_effective_at,
      count(*) FILTER (WHERE mo.completeness_status = 'complete')::bigint AS complete_observations,
      count(*) FILTER (WHERE mo.freshness_status = 'fresh')::bigint AS fresh_observations
    FROM growth.social_accounts sa
    JOIN growth.metric_observations mo
      ON mo.workspace_id = sa.workspace_id
     AND mo.social_account_id = sa.id
    WHERE sa.workspace_id = p_workspace_id
      AND coalesce(mo.provider_effective_at, mo.observed_at) >= p_from
      AND coalesce(mo.provider_effective_at, mo.observed_at) < p_to
    GROUP BY sa.id, sa.platform, sa.provider_account_id, sa.handle, mo.metric_name
  ),
  classified AS (
    SELECT
      grouped.*,
      CASE
        WHEN complete_observations < observation_count THEN 'incomplete'
        WHEN fresh_observations < observation_count THEN 'stale'
        ELSE 'ok'
      END AS quality_status,
      CASE
        WHEN complete_observations < observation_count THEN 'incomplete_observations'
        WHEN fresh_observations < observation_count THEN 'stale_observations'
        ELSE NULL
      END AS anomaly_reason,
      complete_observations::numeric / NULLIF(observation_count, 0)::numeric AS completeness_ratio,
      fresh_observations::numeric / NULLIF(observation_count, 0)::numeric AS freshness_ratio
    FROM grouped
  )
  SELECT
    classified.social_account_id,
    classified.platform,
    classified.provider_account_id,
    classified.handle,
    classified.metric_name,
    classified.observation_count,
    classified.latest_observed_at,
    classified.latest_effective_at,
    classified.complete_observations,
    classified.fresh_observations,
    classified.quality_status,
    classified.anomaly_reason,
    classified.completeness_ratio,
    classified.freshness_ratio
  FROM classified
  WHERE classified.quality_status <> 'ok'
  ORDER BY classified.quality_status, classified.platform, classified.handle NULLS LAST, classified.metric_name;
END;
$$;

ALTER FUNCTION growth.list_metric_quality_anomalies(uuid,timestamptz,timestamptz)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.list_metric_quality_anomalies(uuid,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.list_metric_quality_anomalies(uuid,timestamptz,timestamptz) TO app_runtime;

COMMIT;
