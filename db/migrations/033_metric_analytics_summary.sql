-- Forward-only analytics projection for provenance-complete metric summaries.
-- The helper exposes aggregate evidence only through the active tenant context.
BEGIN;

CREATE OR REPLACE FUNCTION growth.list_metric_analytics_summary(
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
  total_value numeric,
  latest_observed_at timestamptz,
  latest_effective_at timestamptz,
  complete_observations bigint,
  fresh_observations bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id THEN
    RAISE EXCEPTION 'analytics workspace context mismatch';
  END IF;

  IF p_from IS NULL OR p_to IS NULL OR p_to <= p_from THEN
    RAISE EXCEPTION 'analytics window must be positive';
  END IF;

  IF p_to - p_from > interval '366 days' THEN
    RAISE EXCEPTION 'analytics window exceeds maximum range';
  END IF;

  RETURN QUERY
  SELECT
    sa.id,
    sa.platform,
    sa.provider_account_id,
    sa.handle,
    mo.metric_name,
    count(*)::bigint,
    sum(mo.raw_value),
    max(mo.observed_at),
    max(coalesce(mo.provider_effective_at, mo.observed_at)),
    count(*) FILTER (WHERE mo.completeness_status = 'complete')::bigint,
    count(*) FILTER (WHERE mo.freshness_status = 'fresh')::bigint
  FROM growth.social_accounts sa
  JOIN growth.metric_observations mo
    ON mo.workspace_id = sa.workspace_id
   AND mo.social_account_id = sa.id
  WHERE sa.workspace_id = p_workspace_id
    AND coalesce(mo.provider_effective_at, mo.observed_at) >= p_from
    AND coalesce(mo.provider_effective_at, mo.observed_at) < p_to
  GROUP BY sa.id, sa.platform, sa.provider_account_id, sa.handle, mo.metric_name
  ORDER BY sa.platform, sa.handle NULLS LAST, mo.metric_name;
END;
$$;

ALTER FUNCTION growth.list_metric_analytics_summary(uuid,timestamptz,timestamptz)
  OWNER TO growth_migrator;

REVOKE ALL ON FUNCTION growth.list_metric_analytics_summary(uuid,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.list_metric_analytics_summary(uuid,timestamptz,timestamptz) TO app_runtime;

COMMIT;
