-- Growth OS — deterministic YouTube Growth Intelligence Engine (Issue #26).
-- Forward-only migration 015.
--
-- This slice derives a factual views-acceleration signal only from:
-- authorized YouTube observations, complete/fresh provenance, and an account
-- with contractually granted authority. It does not use derived analytics,
-- causal claims, external benchmarks, or synthetic fallback data.

BEGIN;
SET search_path = growth, public;

CREATE TABLE growth.factual_signals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  social_account_id uuid NOT NULL,
  signal_type text NOT NULL CHECK (signal_type IN ('views_acceleration')),
  metric_name text NOT NULL,
  status text NOT NULL CHECK (status IN ('active','insufficient_signal','expired')),
  latest_observation_id uuid NOT NULL,
  observation_ids uuid[] NOT NULL DEFAULT '{}',
  latest_value numeric NOT NULL,
  baseline_value numeric NOT NULL,
  delta_ratio numeric NOT NULL,
  sample_size integer NOT NULL CHECK (sample_size >= 0),
  confidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  logic_version text NOT NULL,
  source_window_start timestamptz NOT NULL,
  source_window_end timestamptz NOT NULL,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  UNIQUE (workspace_id,social_account_id,signal_type,metric_name,source_window_end,logic_version),
  FOREIGN KEY (workspace_id,social_account_id)
    REFERENCES growth.social_accounts(workspace_id,id),
  FOREIGN KEY (workspace_id,latest_observation_id)
    REFERENCES growth.metric_observations(workspace_id,id)
);

ALTER TABLE growth.insights
  ADD COLUMN source_signal_id uuid,
  ADD CONSTRAINT insights_source_signal_uq UNIQUE (workspace_id,source_signal_id),
  ADD CONSTRAINT insights_source_signal_fk
    FOREIGN KEY (workspace_id,source_signal_id)
    REFERENCES growth.factual_signals(workspace_id,id);

ALTER TABLE growth.opportunities
  ADD COLUMN source_signal_id uuid,
  ADD CONSTRAINT opportunities_source_signal_uq UNIQUE (workspace_id,source_signal_id),
  ADD CONSTRAINT opportunities_source_signal_fk
    FOREIGN KEY (workspace_id,source_signal_id)
    REFERENCES growth.factual_signals(workspace_id,id);

ALTER TABLE growth.factual_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.factual_signals FORCE ROW LEVEL SECURITY;

CREATE POLICY factual_signals_workspace_isolation
  ON growth.factual_signals
  USING (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
  )
  WITH CHECK (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
  );

ALTER TABLE growth.factual_signals OWNER TO growth_migrator;
REVOKE ALL ON TABLE growth.factual_signals FROM PUBLIC;
REVOKE ALL ON TABLE growth.factual_signals FROM app_runtime;

CREATE OR REPLACE FUNCTION growth.recompute_youtube_growth_intelligence(
  p_social_account_id uuid
)
RETURNS TABLE (
  signal_id uuid,
  insight_id uuid,
  opportunity_id uuid,
  result_status text,
  observations_used integer,
  delta_ratio numeric
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ws uuid := growth.current_workspace_id();
  v_market text;
  v_latest_id uuid;
  v_observation_ids uuid[];
  v_latest_value numeric;
  v_baseline_value numeric;
  v_latest_at timestamptz;
  v_window_start timestamptz;
  v_sample_size integer := 0;
  v_delta_ratio numeric;
  v_signal_id uuid;
  v_insight_id uuid;
  v_opportunity_id uuid;
  v_logic_version constant text := 'growth.youtube.views-acceleration.v1';
  v_confidence jsonb;
  v_expires_at timestamptz := now() + interval '7 days';
BEGIN
  IF ws IS NULL
     OR growth.current_app_user_id() IS NULL
     OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'growth intelligence requires active tenant context';
  END IF;

  SELECT sa.market
    INTO v_market
    FROM growth.social_accounts sa
    JOIN growth.platform_connections pc
      ON pc.workspace_id = sa.workspace_id
     AND pc.id = sa.platform_connection_id
    JOIN growth.managed_accounts ma
      ON ma.workspace_id = sa.workspace_id
     AND ma.id = sa.managed_account_id
   WHERE sa.workspace_id = ws
     AND sa.id = p_social_account_id
     AND sa.platform = 'youtube'
     AND pc.state = 'connected'
     AND ma.authority_status = 'contractually_granted';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'growth intelligence requires connected authorized YouTube account';
  END IF;

  WITH ranked AS (
    SELECT mo.id,
           mo.raw_value,
           mo.provider_effective_at,
           mo.observed_at,
           row_number() OVER (
             ORDER BY mo.provider_effective_at DESC NULLS LAST,
                      mo.observed_at DESC,
                      mo.id
           ) AS rn
      FROM growth.metric_observations mo
     WHERE mo.workspace_id = ws
       AND mo.social_account_id = p_social_account_id
       AND mo.metric_name = 'views'
       AND mo.authorization_class = 'authorized_account'
       AND mo.completeness_status = 'complete'
       AND mo.freshness_status = 'fresh'
     ORDER BY mo.provider_effective_at DESC NULLS LAST,
              mo.observed_at DESC,
              mo.id
     LIMIT 8
  )
  SELECT count(*)::integer,
         (array_agg(id ORDER BY rn))[1],
         array_agg(id ORDER BY rn),
         max(raw_value) FILTER (WHERE rn = 1),
         avg(raw_value) FILTER (WHERE rn > 1),
         max(provider_effective_at) FILTER (WHERE rn = 1),
         min(provider_effective_at)
    INTO v_sample_size,
         v_latest_id,
         v_observation_ids,
         v_latest_value,
         v_baseline_value,
         v_latest_at,
         v_window_start
    FROM ranked;

  IF v_sample_size < 3
     OR v_latest_id IS NULL
     OR v_baseline_value IS NULL
     OR v_baseline_value <= 0
     OR v_latest_at IS NULL
     OR v_window_start IS NULL THEN
    RETURN QUERY SELECT
      NULL::uuid,
      NULL::uuid,
      NULL::uuid,
      'insufficient_signal'::text,
      v_sample_size,
      NULL::numeric;
    RETURN;
  END IF;

  v_delta_ratio := (v_latest_value - v_baseline_value) / v_baseline_value;

  IF v_delta_ratio < 0.25 THEN
    RETURN QUERY SELECT
      NULL::uuid,
      NULL::uuid,
      NULL::uuid,
      'insufficient_signal'::text,
      v_sample_size,
      v_delta_ratio;
    RETURN;
  END IF;

  v_confidence := jsonb_build_object(
    'level', CASE
      WHEN v_sample_size >= 7 AND v_delta_ratio >= 0.5 THEN 'high'
      ELSE 'medium'
    END,
    'method', 'latest views vs mean of previous complete observations',
    'threshold_ratio', 0.25,
    'causal_claim', false
  );

  INSERT INTO growth.factual_signals (
    workspace_id,
    social_account_id,
    signal_type,
    metric_name,
    status,
    latest_observation_id,
    observation_ids,
    latest_value,
    baseline_value,
    delta_ratio,
    sample_size,
    confidence,
    logic_version,
    source_window_start,
    source_window_end,
    expires_at,
    updated_at
  ) VALUES (
    ws,
    p_social_account_id,
    'views_acceleration',
    'views',
    'active',
    v_latest_id,
    v_observation_ids,
    v_latest_value,
    v_baseline_value,
    v_delta_ratio,
    v_sample_size,
    v_confidence,
    v_logic_version,
    v_window_start,
    v_latest_at,
    v_expires_at,
    now()
  )
  ON CONFLICT (
    workspace_id,
    social_account_id,
    signal_type,
    metric_name,
    source_window_end,
    logic_version
  ) DO UPDATE SET
    latest_observation_id = EXCLUDED.latest_observation_id,
    observation_ids = EXCLUDED.observation_ids,
    latest_value = EXCLUDED.latest_value,
    baseline_value = EXCLUDED.baseline_value,
    delta_ratio = EXCLUDED.delta_ratio,
    sample_size = EXCLUDED.sample_size,
    confidence = EXCLUDED.confidence,
    status = EXCLUDED.status,
    source_window_start = EXCLUDED.source_window_start,
    expires_at = EXCLUDED.expires_at,
    updated_at = now()
  RETURNING id INTO v_signal_id;

  INSERT INTO growth.insights (
    id,
    workspace_id,
    social_account_id,
    source_signal_id,
    state,
    claim,
    metric_definition,
    sample_size,
    confidence,
    logic_version,
    valid_from,
    expires_at
  ) VALUES (
    gen_random_uuid(),
    ws,
    p_social_account_id,
    v_signal_id,
    'confirmed_account',
    format(
      'YouTube views are %s%% above this account''s recent baseline.',
      round(v_delta_ratio * 100, 1)
    ),
    jsonb_build_object(
      'metric', 'views',
      'baseline', 'mean_previous_complete_observations',
      'latest_observation_id', v_latest_id,
      'threshold_ratio', 0.25
    ),
    v_sample_size,
    v_confidence,
    v_logic_version,
    now(),
    v_expires_at
  )
  ON CONFLICT (workspace_id,source_signal_id) DO UPDATE SET
    claim = EXCLUDED.claim,
    metric_definition = EXCLUDED.metric_definition,
    sample_size = EXCLUDED.sample_size,
    confidence = EXCLUDED.confidence,
    valid_from = EXCLUDED.valid_from,
    expires_at = EXCLUDED.expires_at
  RETURNING id INTO v_insight_id;

  INSERT INTO growth.insight_evidence (
    id,
    workspace_id,
    insight_id,
    evidence_type,
    evidence_ref,
    source_class,
    weight
  )
  SELECT
    gen_random_uuid(),
    ws,
    v_insight_id,
    'metric_observation',
    'metric_observation:' || observation_id::text,
    'owned',
    CASE WHEN observation_id = v_latest_id THEN 1.0 ELSE 0.5 END
    FROM unnest(v_observation_ids) AS observation_id
  ON CONFLICT (insight_id,evidence_type,evidence_ref) DO UPDATE SET
    weight = EXCLUDED.weight;

  INSERT INTO growth.opportunities (
    id,
    workspace_id,
    social_account_id,
    source_signal_id,
    market,
    platform,
    status,
    score,
    confidence,
    ranking_version,
    expires_at
  ) VALUES (
    gen_random_uuid(),
    ws,
    p_social_account_id,
    v_signal_id,
    coalesce(nullif(v_market,''), 'global'),
    'youtube',
    'active',
    least(100::numeric, greatest(0::numeric, round(50 + v_delta_ratio * 100, 1))),
    v_confidence,
    v_logic_version,
    v_expires_at
  )
  ON CONFLICT (workspace_id,source_signal_id) DO UPDATE SET
    market = EXCLUDED.market,
    status = EXCLUDED.status,
    score = EXCLUDED.score,
    confidence = EXCLUDED.confidence,
    ranking_version = EXCLUDED.ranking_version,
    expires_at = EXCLUDED.expires_at
  RETURNING id INTO v_opportunity_id;

  INSERT INTO growth.opportunity_evidence (
    id,
    workspace_id,
    opportunity_id,
    source_class,
    evidence_ref,
    observed_at
  )
  SELECT
    gen_random_uuid(),
    ws,
    v_opportunity_id,
    'owned',
    'metric_observation:' || observation_id::text,
    v_latest_at
    FROM unnest(v_observation_ids) AS observation_id
  ON CONFLICT (opportunity_id,source_class,evidence_ref) DO UPDATE SET
    observed_at = EXCLUDED.observed_at;

  RETURN QUERY SELECT
    v_signal_id,
    v_insight_id,
    v_opportunity_id,
    'opportunity_created'::text,
    v_sample_size,
    v_delta_ratio;
END;
$$;

ALTER FUNCTION growth.recompute_youtube_growth_intelligence(uuid) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.recompute_youtube_growth_intelligence(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.recompute_youtube_growth_intelligence(uuid) TO app_runtime;

COMMIT;
