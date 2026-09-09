-- Growth OS — commercial entitlements and enterprise governance foundation.
-- Forward-only migration 038.
-- Provider billing is intentionally represented by auditable internal state only.

BEGIN;
SET search_path = growth, public;

CREATE TABLE growth.billing_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE CHECK (code IN ('free','pro','enterprise')),
  display_name text NOT NULL,
  monthly_action_limit integer NOT NULL CHECK (monthly_action_limit BETWEEN 0 AND 1000000),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO growth.billing_plans (code, display_name, monthly_action_limit)
VALUES
  ('free', 'Free', 100),
  ('pro', 'Pro', 5000),
  ('enterprise', 'Enterprise', 1000000)
ON CONFLICT (code) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  monthly_action_limit = EXCLUDED.monthly_action_limit,
  active = true;

CREATE TABLE growth.workspace_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  plan_id uuid NOT NULL REFERENCES growth.billing_plans(id),
  status text NOT NULL DEFAULT 'trialing'
    CHECK (status IN ('trialing','active','past_due','cancelled')),
  provider_customer_ref text,
  provider_subscription_ref text,
  current_period_start timestamptz NOT NULL DEFAULT date_trunc('month', now()),
  current_period_end timestamptz NOT NULL DEFAULT (date_trunc('month', now()) + interval '1 month'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id),
  UNIQUE (workspace_id, id),
  CHECK (current_period_end > current_period_start)
);

CREATE TABLE growth.usage_counters (
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  period_start timestamptz NOT NULL,
  metric_key text NOT NULL CHECK (metric_key IN ('automation_requests','api_calls','storage_bytes')),
  used_units bigint NOT NULL DEFAULT 0 CHECK (used_units >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workspace_id, period_start, metric_key)
);

CREATE TABLE growth.enterprise_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  data_retention_days integer NOT NULL DEFAULT 365 CHECK (data_retention_days BETWEEN 30 AND 3650),
  support_tier text NOT NULL DEFAULT 'standard'
    CHECK (support_tier IN ('standard','priority','dedicated')),
  legal_acceptance_ref text,
  deletion_requested_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id),
  UNIQUE (workspace_id, id)
);

ALTER TABLE growth.workspace_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.workspace_subscriptions FORCE ROW LEVEL SECURITY;
CREATE POLICY workspace_subscriptions_workspace_isolation ON growth.workspace_subscriptions
  USING (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id));

ALTER TABLE growth.usage_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.usage_counters FORCE ROW LEVEL SECURITY;
CREATE POLICY usage_counters_workspace_isolation ON growth.usage_counters
  USING (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id));

ALTER TABLE growth.enterprise_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.enterprise_policies FORCE ROW LEVEL SECURITY;
CREATE POLICY enterprise_policies_workspace_isolation ON growth.enterprise_policies
  USING (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id));

ALTER TABLE growth.billing_plans OWNER TO growth_migrator;
ALTER TABLE growth.workspace_subscriptions OWNER TO growth_migrator;
ALTER TABLE growth.usage_counters OWNER TO growth_migrator;
ALTER TABLE growth.enterprise_policies OWNER TO growth_migrator;
REVOKE ALL ON TABLE growth.billing_plans FROM PUBLIC;
REVOKE ALL ON TABLE growth.billing_plans FROM app_runtime;
REVOKE ALL ON TABLE growth.workspace_subscriptions FROM PUBLIC;
REVOKE ALL ON TABLE growth.workspace_subscriptions FROM app_runtime;
REVOKE ALL ON TABLE growth.usage_counters FROM PUBLIC;
REVOKE ALL ON TABLE growth.usage_counters FROM app_runtime;
REVOKE ALL ON TABLE growth.enterprise_policies FROM PUBLIC;
REVOKE ALL ON TABLE growth.enterprise_policies FROM app_runtime;

CREATE OR REPLACE FUNCTION growth.get_workspace_entitlements(p_workspace_id uuid)
RETURNS TABLE (
  plan_code text,
  plan_name text,
  subscription_status text,
  monthly_action_limit integer,
  used_automation_requests bigint,
  period_start timestamptz,
  period_end timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'commercial workspace context mismatch';
  END IF;

  RETURN QUERY
  SELECT p.code,
         p.display_name,
         coalesce(s.status, 'trialing'),
         p.monthly_action_limit,
         coalesce(u.used_units, 0),
         date_trunc('month', now()),
         date_trunc('month', now()) + interval '1 month'
    FROM growth.billing_plans p
    LEFT JOIN growth.workspace_subscriptions s
      ON s.workspace_id = p_workspace_id AND s.plan_id = p.id
    LEFT JOIN growth.usage_counters u
      ON u.workspace_id = p_workspace_id
     AND u.period_start = date_trunc('month', now())
     AND u.metric_key = 'automation_requests'
   WHERE p.code = coalesce((
     SELECT sp.code
       FROM growth.workspace_subscriptions ss
       JOIN growth.billing_plans sp ON sp.id = ss.plan_id
      WHERE ss.workspace_id = p_workspace_id
   ), 'free');
END;
$$;

CREATE OR REPLACE FUNCTION growth.record_usage(
  p_workspace_id uuid,
  p_metric_key text,
  p_units bigint
)
RETURNS growth.usage_counters
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_limit bigint;
  v_used bigint;
  v_row growth.usage_counters;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'commercial workspace context mismatch';
  END IF;
  IF p_metric_key NOT IN ('automation_requests','api_calls','storage_bytes')
     OR p_units IS NULL OR p_units < 1
  THEN
    RAISE EXCEPTION 'usage increment is invalid';
  END IF;

  SELECT monthly_action_limit::bigint INTO v_limit
    FROM growth.get_workspace_entitlements(p_workspace_id);
  SELECT coalesce(used_units, 0) INTO v_used
    FROM growth.usage_counters
   WHERE workspace_id = p_workspace_id
     AND period_start = date_trunc('month', now())
     AND metric_key = p_metric_key
   FOR UPDATE;

  IF p_metric_key = 'automation_requests' AND v_used + p_units > v_limit THEN
    RAISE EXCEPTION 'commercial entitlement limit reached';
  END IF;

  INSERT INTO growth.usage_counters (
    workspace_id, period_start, metric_key, used_units
  ) VALUES (
    p_workspace_id, date_trunc('month', now()), p_metric_key, p_units
  )
  ON CONFLICT (workspace_id, period_start, metric_key) DO UPDATE SET
    used_units = growth.usage_counters.used_units + EXCLUDED.used_units,
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION growth.set_workspace_subscription(
  p_workspace_id uuid,
  p_plan_code text,
  p_status text,
  p_provider_customer_ref text,
  p_provider_subscription_ref text
)
RETURNS growth.workspace_subscriptions
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_plan_id uuid;
  v_row growth.workspace_subscriptions;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'commercial workspace context mismatch';
  END IF;
  IF p_status NOT IN ('trialing','active','past_due','cancelled') THEN
    RAISE EXCEPTION 'subscription status is invalid';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.memberships m
     WHERE m.workspace_id = p_workspace_id
       AND m.user_id = growth.current_app_user_id()
       AND m.status = 'active'
       AND m.role IN ('owner','admin')
  ) THEN
    RAISE EXCEPTION 'subscription management requires owner or admin';
  END IF;

  SELECT id INTO v_plan_id FROM growth.billing_plans
   WHERE code = p_plan_code AND active;
  IF v_plan_id IS NULL THEN
    RAISE EXCEPTION 'billing plan is unavailable';
  END IF;

  INSERT INTO growth.workspace_subscriptions (
    workspace_id, plan_id, status, provider_customer_ref, provider_subscription_ref
  ) VALUES (
    p_workspace_id, v_plan_id, p_status, p_provider_customer_ref, p_provider_subscription_ref
  )
  ON CONFLICT (workspace_id) DO UPDATE SET
    plan_id = EXCLUDED.plan_id,
    status = EXCLUDED.status,
    provider_customer_ref = EXCLUDED.provider_customer_ref,
    provider_subscription_ref = EXCLUDED.provider_subscription_ref,
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION growth.get_enterprise_policy(p_workspace_id uuid)
RETURNS growth.enterprise_policies
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.enterprise_policies;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'commercial workspace context mismatch';
  END IF;

  SELECT * INTO v_row FROM growth.enterprise_policies
   WHERE workspace_id = p_workspace_id;
  IF NOT FOUND THEN
    RETURN ROW(
      NULL::uuid, p_workspace_id, 365, 'standard', NULL::text, NULL::timestamptz,
      now(), now()
    )::growth.enterprise_policies;
  END IF;
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION growth.set_enterprise_policy(
  p_workspace_id uuid,
  p_retention_days integer,
  p_support_tier text,
  p_legal_acceptance_ref text
)
RETURNS growth.enterprise_policies
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.enterprise_policies;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'commercial workspace context mismatch';
  END IF;
  IF p_retention_days NOT BETWEEN 30 AND 3650
     OR p_support_tier NOT IN ('standard','priority','dedicated')
  THEN
    RAISE EXCEPTION 'enterprise policy is invalid';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.memberships m
     WHERE m.workspace_id = p_workspace_id
       AND m.user_id = growth.current_app_user_id()
       AND m.status = 'active'
       AND m.role IN ('owner','admin')
  ) THEN
    RAISE EXCEPTION 'enterprise policy requires owner or admin';
  END IF;

  INSERT INTO growth.enterprise_policies (
    workspace_id, data_retention_days, support_tier, legal_acceptance_ref
  ) VALUES (
    p_workspace_id, p_retention_days, p_support_tier, p_legal_acceptance_ref
  )
  ON CONFLICT (workspace_id) DO UPDATE SET
    data_retention_days = EXCLUDED.data_retention_days,
    support_tier = EXCLUDED.support_tier,
    legal_acceptance_ref = EXCLUDED.legal_acceptance_ref,
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

ALTER FUNCTION growth.get_workspace_entitlements(uuid) OWNER TO growth_migrator;
ALTER FUNCTION growth.record_usage(uuid,text,bigint) OWNER TO growth_migrator;
ALTER FUNCTION growth.set_workspace_subscription(uuid,text,text,text,text) OWNER TO growth_migrator;
ALTER FUNCTION growth.get_enterprise_policy(uuid) OWNER TO growth_migrator;
ALTER FUNCTION growth.set_enterprise_policy(uuid,integer,text,text) OWNER TO growth_migrator;

REVOKE ALL ON FUNCTION growth.get_workspace_entitlements(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.record_usage(uuid,text,bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.set_workspace_subscription(uuid,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.get_enterprise_policy(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.set_enterprise_policy(uuid,integer,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.get_workspace_entitlements(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.record_usage(uuid,text,bigint) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.set_workspace_subscription(uuid,text,text,text,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.get_enterprise_policy(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.set_enterprise_policy(uuid,integer,text,text) TO app_runtime;

COMMIT;
