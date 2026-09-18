-- Growth OS — approval-gated automation action execution.
-- Forward-only migration 068.
-- Approval and execution are distinct. Provider actions require explicit bound payloads.

BEGIN;
SET search_path = growth, public;

ALTER TABLE growth.automation_action_requests
  ADD COLUMN action_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN execution_status text NOT NULL DEFAULT 'not_ready'
    CHECK (execution_status IN ('not_ready','ready','executing','succeeded','needs_input','failed')),
  ADD COLUMN execution_result_ref text
    CHECK (execution_result_ref IS NULL OR char_length(execution_result_ref) <= 1000),
  ADD COLUMN execution_error_class text
    CHECK (execution_error_class IS NULL OR char_length(execution_error_class) <= 200),
  ADD COLUMN execution_started_at timestamptz,
  ADD COLUMN executed_at timestamptz,
  ADD COLUMN execution_attempts integer NOT NULL DEFAULT 0 CHECK (execution_attempts >= 0),
  ADD CONSTRAINT automation_action_payload_object
    CHECK (jsonb_typeof(action_payload) = 'object');

CREATE INDEX automation_requests_workspace_execution_idx
  ON growth.automation_action_requests(workspace_id, execution_status, created_at DESC);

CREATE OR REPLACE FUNCTION growth.list_automation_action_requests_v2(
  p_workspace_id uuid,
  p_limit integer
)
RETURNS SETOF growth.automation_action_requests
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
  SELECT r.*
    FROM growth.automation_action_requests r
   WHERE r.workspace_id = p_workspace_id
   ORDER BY r.created_at DESC, r.id
   LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION growth.create_automation_action_request_v2(
  p_workspace_id uuid,
  p_action_code text,
  p_target_ref text,
  p_evidence_ref text,
  p_note text,
  p_action_payload jsonb
)
RETURNS growth.automation_action_requests
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.automation_action_requests;
BEGIN
  IF p_action_payload IS NULL OR jsonb_typeof(p_action_payload) <> 'object' THEN
    RAISE EXCEPTION 'automation action payload must be an object';
  END IF;
  IF pg_column_size(p_action_payload) > 65536 THEN
    RAISE EXCEPTION 'automation action payload is too large';
  END IF;

  SELECT * INTO v_row
    FROM growth.create_automation_action_request(
      p_workspace_id,
      p_action_code,
      p_target_ref,
      p_evidence_ref,
      p_note
    );

  UPDATE growth.automation_action_requests
     SET action_payload = p_action_payload
   WHERE workspace_id = p_workspace_id
     AND id = v_row.id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION growth.decide_automation_action_request_v2(
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
  v_row growth.automation_action_requests;
BEGIN
  PERFORM growth.decide_automation_action_request(
    p_workspace_id,
    p_request_id,
    p_decision,
    p_note
  );

  UPDATE growth.automation_action_requests
     SET execution_status = CASE
           WHEN p_decision = 'approve' THEN 'ready'
           ELSE 'not_ready'
         END,
         execution_result_ref = NULL,
         execution_error_class = NULL,
         execution_started_at = NULL,
         executed_at = NULL
   WHERE workspace_id = p_workspace_id
     AND id = p_request_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION growth.claim_automation_action_execution(
  p_workspace_id uuid,
  p_request_id uuid
)
RETURNS growth.automation_action_requests
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.automation_action_requests;
  v_policy growth.automation_policies;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'automation workspace context mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM growth.memberships m
     WHERE m.workspace_id = p_workspace_id
       AND m.user_id = growth.current_app_user_id()
       AND m.status = 'active'
       AND m.role IN ('owner','admin')
  ) THEN
    RAISE EXCEPTION 'automation execution requires owner or admin';
  END IF;

  SELECT p.* INTO v_policy
    FROM growth.automation_policies p
   WHERE p.workspace_id = p_workspace_id
   FOR UPDATE;
  IF NOT FOUND OR v_policy.mode = 'disabled' OR v_policy.kill_switch THEN
    RAISE EXCEPTION 'automation execution blocked by policy or kill switch';
  END IF;

  UPDATE growth.automation_action_requests r
     SET execution_status = 'executing',
         execution_started_at = now(),
         executed_at = NULL,
         execution_result_ref = NULL,
         execution_error_class = NULL,
         execution_attempts = execution_attempts + 1
   WHERE r.workspace_id = p_workspace_id
     AND r.id = p_request_id
     AND r.status = 'approved'
     AND r.execution_status = 'ready'
  RETURNING r.* INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'automation request is not approved and ready for execution';
  END IF;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION growth.finalize_automation_action_execution(
  p_workspace_id uuid,
  p_request_id uuid,
  p_execution_status text,
  p_result_ref text,
  p_error_class text
)
RETURNS growth.automation_action_requests
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.automation_action_requests;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'automation workspace context mismatch';
  END IF;
  IF p_execution_status NOT IN ('succeeded','needs_input','failed') THEN
    RAISE EXCEPTION 'automation execution final status is invalid';
  END IF;
  IF p_execution_status = 'succeeded'
     AND (p_result_ref IS NULL OR char_length(trim(p_result_ref)) = 0)
  THEN
    RAISE EXCEPTION 'successful automation execution requires result reference';
  END IF;
  IF p_execution_status IN ('needs_input','failed')
     AND (p_error_class IS NULL OR char_length(trim(p_error_class)) = 0)
  THEN
    RAISE EXCEPTION 'unsuccessful automation execution requires error class';
  END IF;
  IF p_result_ref IS NOT NULL AND char_length(p_result_ref) > 1000 THEN
    RAISE EXCEPTION 'automation execution result reference is too long';
  END IF;
  IF p_error_class IS NOT NULL AND char_length(p_error_class) > 200 THEN
    RAISE EXCEPTION 'automation execution error class is too long';
  END IF;

  UPDATE growth.automation_action_requests r
     SET execution_status = p_execution_status,
         execution_result_ref = nullif(trim(p_result_ref), ''),
         execution_error_class = nullif(trim(p_error_class), ''),
         executed_at = now()
   WHERE r.workspace_id = p_workspace_id
     AND r.id = p_request_id
     AND r.status = 'approved'
     AND r.execution_status = 'executing'
  RETURNING r.* INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'automation execution is not currently claimed';
  END IF;

  RETURN v_row;
END;
$$;

ALTER FUNCTION growth.list_automation_action_requests_v2(uuid,integer) OWNER TO growth_migrator;
ALTER FUNCTION growth.create_automation_action_request_v2(uuid,text,text,text,text,jsonb) OWNER TO growth_migrator;
ALTER FUNCTION growth.decide_automation_action_request_v2(uuid,uuid,text,text) OWNER TO growth_migrator;
ALTER FUNCTION growth.claim_automation_action_execution(uuid,uuid) OWNER TO growth_migrator;
ALTER FUNCTION growth.finalize_automation_action_execution(uuid,uuid,text,text,text) OWNER TO growth_migrator;

REVOKE ALL ON FUNCTION growth.list_automation_action_requests_v2(uuid,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.create_automation_action_request_v2(uuid,text,text,text,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.decide_automation_action_request_v2(uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.claim_automation_action_execution(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.finalize_automation_action_execution(uuid,uuid,text,text,text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION growth.list_automation_action_requests_v2(uuid,integer) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.create_automation_action_request_v2(uuid,text,text,text,text,jsonb) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.decide_automation_action_request_v2(uuid,uuid,text,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.claim_automation_action_execution(uuid,uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.finalize_automation_action_execution(uuid,uuid,text,text,text) TO app_runtime;

COMMIT;
