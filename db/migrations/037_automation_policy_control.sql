-- Growth OS — approval-gated automation control plane.
-- Forward-only migration 037.
-- Requests are auditable and bounded; no provider execution happens here.

BEGIN;
SET search_path = growth, public;

CREATE TABLE growth.automation_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  mode text NOT NULL DEFAULT 'approval_required'
    CHECK (mode IN ('approval_required','disabled')),
  daily_request_limit integer NOT NULL DEFAULT 10
    CHECK (daily_request_limit BETWEEN 0 AND 1000),
  kill_switch boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id),
  UNIQUE (workspace_id, id)
);

CREATE TABLE growth.automation_action_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  policy_id uuid NOT NULL,
  action_code text NOT NULL
    CHECK (action_code IN ('draft_content','review_evidence','plan_experiment','publish_content','multiply_variant')),
  target_ref text NOT NULL CHECK (char_length(trim(target_ref)) BETWEEN 1 AND 500),
  evidence_ref text CHECK (evidence_ref IS NULL OR char_length(trim(evidence_ref)) BETWEEN 1 AND 1000),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  requested_by uuid NOT NULL REFERENCES growth.users(id),
  approved_by uuid REFERENCES growth.users(id),
  note text CHECK (note IS NULL OR char_length(note) <= 1000),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  UNIQUE (workspace_id, id),
  FOREIGN KEY (workspace_id, policy_id)
    REFERENCES growth.automation_policies(workspace_id, id),
  CHECK (status = 'pending' OR decided_at IS NOT NULL),
  CHECK (status <> 'approved' OR approved_by IS NOT NULL)
);

ALTER TABLE growth.automation_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.automation_policies FORCE ROW LEVEL SECURITY;
CREATE POLICY automation_policies_workspace_isolation ON growth.automation_policies
  USING (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id));

ALTER TABLE growth.automation_action_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.automation_action_requests FORCE ROW LEVEL SECURITY;
CREATE POLICY automation_action_requests_workspace_isolation ON growth.automation_action_requests
  USING (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id));

CREATE INDEX automation_requests_workspace_status_idx
  ON growth.automation_action_requests(workspace_id, status, created_at DESC);

ALTER TABLE growth.automation_policies OWNER TO growth_migrator;
ALTER TABLE growth.automation_action_requests OWNER TO growth_migrator;
REVOKE ALL ON TABLE growth.automation_policies FROM PUBLIC;
REVOKE ALL ON TABLE growth.automation_policies FROM app_runtime;
REVOKE ALL ON TABLE growth.automation_action_requests FROM PUBLIC;
REVOKE ALL ON TABLE growth.automation_action_requests FROM app_runtime;

CREATE OR REPLACE FUNCTION growth.get_automation_policy(p_workspace_id uuid)
RETURNS TABLE (
  id uuid,
  workspace_id uuid,
  mode text,
  daily_request_limit integer,
  kill_switch boolean,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'automation workspace context mismatch';
  END IF;

  RETURN QUERY
  SELECT p.id, p.workspace_id, p.mode, p.daily_request_limit, p.kill_switch,
         p.created_at, p.updated_at
    FROM growth.automation_policies p
   WHERE p.workspace_id = p_workspace_id
  UNION ALL
  SELECT NULL::uuid, p_workspace_id, 'approval_required', 10, false,
         now(), now()
   WHERE NOT EXISTS (
     SELECT 1 FROM growth.automation_policies p WHERE p.workspace_id = p_workspace_id
   );
END;
$$;

CREATE OR REPLACE FUNCTION growth.set_automation_policy(
  p_workspace_id uuid,
  p_mode text,
  p_daily_request_limit integer,
  p_kill_switch boolean
)
RETURNS growth.automation_policies
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.automation_policies;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'automation workspace context mismatch';
  END IF;
  IF p_mode NOT IN ('approval_required','disabled')
     OR p_daily_request_limit IS NULL
     OR p_daily_request_limit NOT BETWEEN 0 AND 1000
  THEN
    RAISE EXCEPTION 'automation policy is invalid';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.memberships m
     WHERE m.workspace_id = p_workspace_id
       AND m.user_id = growth.current_app_user_id()
       AND m.status = 'active'
       AND m.role IN ('owner','admin')
  ) THEN
    RAISE EXCEPTION 'automation policy requires owner or admin';
  END IF;

  INSERT INTO growth.automation_policies (
    workspace_id, mode, daily_request_limit, kill_switch
  ) VALUES (
    p_workspace_id, p_mode, p_daily_request_limit, p_kill_switch
  )
  ON CONFLICT (workspace_id) DO UPDATE SET
    mode = EXCLUDED.mode,
    daily_request_limit = EXCLUDED.daily_request_limit,
    kill_switch = EXCLUDED.kill_switch,
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION growth.list_automation_action_requests(
  p_workspace_id uuid,
  p_limit integer
)
RETURNS TABLE (
  id uuid,
  policy_id uuid,
  action_code text,
  target_ref text,
  evidence_ref text,
  status text,
  requested_by uuid,
  approved_by uuid,
  note text,
  created_at timestamptz,
  decided_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'automation workspace context mismatch';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'automation request limit out of range';
  END IF;

  RETURN QUERY
  SELECT r.id, r.policy_id, r.action_code, r.target_ref, r.evidence_ref,
         r.status, r.requested_by, r.approved_by, r.note, r.created_at, r.decided_at
    FROM growth.automation_action_requests r
   WHERE r.workspace_id = p_workspace_id
   ORDER BY r.created_at DESC, r.id
   LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION growth.create_automation_action_request(
  p_workspace_id uuid,
  p_action_code text,
  p_target_ref text,
  p_evidence_ref text,
  p_note text
)
RETURNS growth.automation_action_requests
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_policy growth.automation_policies;
  v_row growth.automation_action_requests;
  v_used integer;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'automation workspace context mismatch';
  END IF;
  IF p_action_code NOT IN ('draft_content','review_evidence','plan_experiment','publish_content','multiply_variant')
     OR p_target_ref IS NULL OR char_length(trim(p_target_ref)) NOT BETWEEN 1 AND 500
  THEN
    RAISE EXCEPTION 'automation request is invalid';
  END IF;
  IF p_evidence_ref IS NULL OR char_length(trim(p_evidence_ref)) NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'automation request requires stored evidence reference';
  END IF;
  IF NOT EXISTS (
    SELECT 1
      FROM growth.opportunity_evidence oe
     WHERE oe.workspace_id = p_workspace_id
       AND (oe.evidence_ref = trim(p_evidence_ref) OR oe.id::text = trim(p_evidence_ref))
       AND (
         p_target_ref !~ '^[0-9a-fA-F-]+$'
         OR oe.opportunity_id::text = trim(p_target_ref)
       )
  ) THEN
    RAISE EXCEPTION 'automation request evidence is not stored for the target';
  END IF;
  IF p_note IS NOT NULL AND char_length(p_note) > 1000 THEN
    RAISE EXCEPTION 'automation request note is too long';
  END IF;

  INSERT INTO growth.automation_policies (workspace_id)
  VALUES (p_workspace_id)
  ON CONFLICT (workspace_id) DO NOTHING;

  SELECT * INTO v_policy
    FROM growth.automation_policies
   WHERE workspace_id = p_workspace_id
   FOR UPDATE;

  IF v_policy.mode = 'disabled' OR v_policy.kill_switch THEN
    RAISE EXCEPTION 'automation is disabled by policy or kill switch';
  END IF;

  SELECT count(*)::integer INTO v_used
    FROM growth.automation_action_requests r
   WHERE r.workspace_id = p_workspace_id
     AND r.created_at >= date_trunc('day', now())
     AND r.status IN ('pending','approved');

  IF v_used >= v_policy.daily_request_limit THEN
    RAISE EXCEPTION 'automation daily request limit reached';
  END IF;

  INSERT INTO growth.automation_action_requests (
    workspace_id, policy_id, action_code, target_ref, evidence_ref,
    status, requested_by, note
  ) VALUES (
    p_workspace_id, v_policy.id, p_action_code, trim(p_target_ref),
    trim(p_evidence_ref), 'pending', growth.current_app_user_id(),
    nullif(trim(p_note), '')
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION growth.decide_automation_action_request(
  p_workspace_id uuid,
  p_request_id uuid,
  p_decision text,
  p_note text
)
RETURNS growth.automation_action_requests
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_request growth.automation_action_requests;
  v_policy growth.automation_policies;
  v_is_admin boolean;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'automation workspace context mismatch';
  END IF;
  IF p_decision NOT IN ('approve','reject','cancel') THEN
    RAISE EXCEPTION 'automation decision is invalid';
  END IF;
  IF p_note IS NOT NULL AND char_length(p_note) > 1000 THEN
    RAISE EXCEPTION 'automation decision note is too long';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM growth.memberships m
     WHERE m.workspace_id = p_workspace_id
       AND m.user_id = growth.current_app_user_id()
       AND m.status = 'active'
       AND m.role IN ('owner','admin')
  ) INTO v_is_admin;

  SELECT * INTO v_request
    FROM growth.automation_action_requests
   WHERE workspace_id = p_workspace_id AND id = p_request_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'automation request not found';
  END IF;
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'automation request is already decided';
  END IF;
  IF p_decision IN ('approve','reject') AND NOT v_is_admin THEN
    RAISE EXCEPTION 'automation approval requires owner or admin';
  END IF;
  IF p_decision = 'cancel'
     AND NOT (v_is_admin OR v_request.requested_by = growth.current_app_user_id())
  THEN
    RAISE EXCEPTION 'automation cancellation requires requester or admin';
  END IF;

  IF p_decision = 'approve' THEN
    SELECT * INTO v_policy FROM growth.automation_policies
     WHERE workspace_id = p_workspace_id FOR UPDATE;
    IF v_policy.kill_switch OR v_policy.mode = 'disabled' THEN
      RAISE EXCEPTION 'automation approval blocked by policy or kill switch';
    END IF;
  END IF;

  UPDATE growth.automation_action_requests
     SET status = CASE p_decision WHEN 'approve' THEN 'approved' WHEN 'reject' THEN 'rejected' ELSE 'cancelled' END,
         approved_by = CASE WHEN p_decision = 'approve' THEN growth.current_app_user_id() ELSE approved_by END,
         note = coalesce(nullif(trim(p_note), ''), note),
         decided_at = now()
   WHERE workspace_id = p_workspace_id AND id = p_request_id
  RETURNING * INTO v_request;

  RETURN v_request;
END;
$$;

ALTER FUNCTION growth.get_automation_policy(uuid) OWNER TO growth_migrator;
ALTER FUNCTION growth.set_automation_policy(uuid,text,integer,boolean) OWNER TO growth_migrator;
ALTER FUNCTION growth.list_automation_action_requests(uuid,integer) OWNER TO growth_migrator;
ALTER FUNCTION growth.create_automation_action_request(uuid,text,text,text,text) OWNER TO growth_migrator;
ALTER FUNCTION growth.decide_automation_action_request(uuid,uuid,text,text) OWNER TO growth_migrator;

REVOKE ALL ON FUNCTION growth.get_automation_policy(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.set_automation_policy(uuid,text,integer,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.list_automation_action_requests(uuid,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.create_automation_action_request(uuid,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.decide_automation_action_request(uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.get_automation_policy(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.set_automation_policy(uuid,text,integer,boolean) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.list_automation_action_requests(uuid,integer) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.create_automation_action_request(uuid,text,text,text,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.decide_automation_action_request(uuid,uuid,text,text) TO app_runtime;

COMMIT;
