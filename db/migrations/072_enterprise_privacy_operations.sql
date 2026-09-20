-- Growth OS — enterprise, support and privacy operations.
-- Forward-only migration 072. No external billing charge or destructive purge
-- is performed by these contracts. Deletion remains request -> tombstone ->
-- separately evidenced purge.

BEGIN;
SET search_path = growth, public;

CREATE TABLE growth.agency_client_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  client_workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  label text NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 120),
  state text NOT NULL DEFAULT 'active' CHECK (state IN ('active','paused')),
  created_by uuid NOT NULL REFERENCES growth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, client_workspace_id),
  CHECK (workspace_id <> client_workspace_id)
);

CREATE TABLE growth.support_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  category text NOT NULL CHECK (category IN ('product','provider','privacy','security','billing')),
  priority text NOT NULL CHECK (priority IN ('normal','high','urgent')),
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open','waiting_customer','resolved','closed')),
  subject text NOT NULL CHECK (length(btrim(subject)) BETWEEN 3 AND 160),
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 3 AND 4000),
  created_by uuid NOT NULL REFERENCES growth.users(id),
  updated_by uuid NOT NULL REFERENCES growth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, id)
);

CREATE TABLE growth.support_case_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  support_case_id uuid NOT NULL,
  actor_user_id uuid NOT NULL REFERENCES growth.users(id),
  prior_state text,
  new_state text NOT NULL CHECK (new_state IN ('open','waiting_customer','resolved','closed')),
  note text NOT NULL CHECK (length(btrim(note)) BETWEEN 1 AND 4000),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, id),
  FOREIGN KEY (workspace_id, support_case_id)
    REFERENCES growth.support_cases(workspace_id, id)
);

ALTER TABLE growth.agency_client_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.agency_client_links FORCE ROW LEVEL SECURITY;
CREATE POLICY agency_client_links_workspace_isolation ON growth.agency_client_links
  USING (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id));

ALTER TABLE growth.support_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.support_cases FORCE ROW LEVEL SECURITY;
CREATE POLICY support_cases_workspace_isolation ON growth.support_cases
  USING (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id));

ALTER TABLE growth.support_case_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.support_case_events FORCE ROW LEVEL SECURITY;
CREATE POLICY support_case_events_workspace_isolation ON growth.support_case_events
  USING (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id));

ALTER TABLE growth.agency_client_links OWNER TO growth_migrator;
ALTER TABLE growth.support_cases OWNER TO growth_migrator;
ALTER TABLE growth.support_case_events OWNER TO growth_migrator;
REVOKE ALL ON TABLE growth.agency_client_links FROM PUBLIC, app_runtime;
REVOKE ALL ON TABLE growth.support_cases FROM PUBLIC, app_runtime;
REVOKE ALL ON TABLE growth.support_case_events FROM PUBLIC, app_runtime;

CREATE OR REPLACE FUNCTION growth.list_agency_clients(p_workspace_id uuid)
RETURNS TABLE(
  link_id uuid,
  client_workspace_id uuid,
  client_workspace_name text,
  label text,
  state text,
  client_role text,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id) THEN
    RAISE EXCEPTION 'agency workspace context mismatch';
  END IF;

  RETURN QUERY
  SELECT l.id, l.client_workspace_id, w.name, l.label, l.state, m.role,
         l.created_at, l.updated_at
    FROM growth.agency_client_links l
    JOIN growth.workspaces w ON w.id = l.client_workspace_id
    JOIN growth.memberships m
      ON m.workspace_id = l.client_workspace_id
     AND m.user_id = growth.current_app_user_id()
     AND m.status = 'active'
   WHERE l.workspace_id = p_workspace_id
   ORDER BY l.label, w.name;
END;
$$;

CREATE OR REPLACE FUNCTION growth.set_agency_client(
  p_workspace_id uuid,
  p_client_workspace_id uuid,
  p_label text,
  p_state text
)
RETURNS growth.agency_client_links
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.agency_client_links;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
     OR p_client_workspace_id IS NULL
     OR p_client_workspace_id = p_workspace_id
     OR length(btrim(coalesce(p_label,''))) NOT BETWEEN 1 AND 120
     OR p_state NOT IN ('active','paused') THEN
    RAISE EXCEPTION 'agency client link is invalid';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.memberships m
     WHERE m.workspace_id = p_workspace_id
       AND m.user_id = growth.current_app_user_id()
       AND m.status = 'active' AND m.role IN ('owner','admin')
  ) OR NOT EXISTS (
    SELECT 1 FROM growth.memberships m
     WHERE m.workspace_id = p_client_workspace_id
       AND m.user_id = growth.current_app_user_id()
       AND m.status = 'active' AND m.role IN ('owner','admin')
  ) THEN
    RAISE EXCEPTION 'agency client management requires administration rights in both workspaces';
  END IF;

  INSERT INTO growth.agency_client_links(
    workspace_id, client_workspace_id, label, state, created_by
  ) VALUES (
    p_workspace_id, p_client_workspace_id, btrim(p_label), p_state,
    growth.current_app_user_id()
  )
  ON CONFLICT (workspace_id, client_workspace_id) DO UPDATE SET
    label = EXCLUDED.label,
    state = EXCLUDED.state,
    updated_at = now()
  RETURNING * INTO v_row;

  INSERT INTO growth.audit_events(
    id, workspace_id, actor_user_id, event_type, resource_type, resource_id, metadata
  ) VALUES (
    gen_random_uuid(), p_workspace_id, growth.current_app_user_id(),
    'agency.client_link.updated', 'agency_client_link', v_row.id,
    jsonb_build_object('client_workspace_id', p_client_workspace_id, 'state', p_state)
  );
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION growth.list_support_cases(p_workspace_id uuid, p_limit integer DEFAULT 50)
RETURNS SETOF growth.support_cases
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id) THEN
    RAISE EXCEPTION 'support workspace context mismatch';
  END IF;
  RETURN QUERY
  SELECT s.* FROM growth.support_cases s
   WHERE s.workspace_id = p_workspace_id
   ORDER BY s.updated_at DESC, s.id
   LIMIT greatest(1, least(coalesce(p_limit,50),100));
END;
$$;

CREATE OR REPLACE FUNCTION growth.create_support_case(
  p_workspace_id uuid,
  p_category text,
  p_priority text,
  p_subject text,
  p_description text
)
RETURNS growth.support_cases
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.support_cases;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
     OR p_category NOT IN ('product','provider','privacy','security','billing')
     OR p_priority NOT IN ('normal','high','urgent')
     OR length(btrim(coalesce(p_subject,''))) NOT BETWEEN 3 AND 160
     OR length(btrim(coalesce(p_description,''))) NOT BETWEEN 3 AND 4000 THEN
    RAISE EXCEPTION 'support case is invalid';
  END IF;

  INSERT INTO growth.support_cases(
    workspace_id, category, priority, subject, description, created_by, updated_by
  ) VALUES (
    p_workspace_id, p_category, p_priority, btrim(p_subject), btrim(p_description),
    growth.current_app_user_id(), growth.current_app_user_id()
  ) RETURNING * INTO v_row;

  INSERT INTO growth.support_case_events(
    workspace_id, support_case_id, actor_user_id, prior_state, new_state, note
  ) VALUES (
    p_workspace_id, v_row.id, growth.current_app_user_id(), NULL, v_row.state,
    'Support case created.'
  );
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION growth.update_support_case(
  p_workspace_id uuid,
  p_case_id uuid,
  p_note text,
  p_new_state text DEFAULT NULL
)
RETURNS growth.support_cases
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_before growth.support_cases;
  v_after growth.support_cases;
  v_state text;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
     OR length(btrim(coalesce(p_note,''))) NOT BETWEEN 1 AND 4000 THEN
    RAISE EXCEPTION 'support case update is invalid';
  END IF;
  SELECT * INTO v_before FROM growth.support_cases
   WHERE workspace_id = p_workspace_id AND id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'support case not found'; END IF;

  v_state := coalesce(p_new_state, v_before.state);
  IF v_state NOT IN ('open','waiting_customer','resolved','closed') THEN
    RAISE EXCEPTION 'support case state is invalid';
  END IF;
  IF v_state <> v_before.state AND NOT (
    (v_before.state = 'open' AND v_state IN ('waiting_customer','resolved','closed'))
    OR (v_before.state = 'waiting_customer' AND v_state IN ('open','resolved','closed'))
    OR (v_before.state = 'resolved' AND v_state IN ('open','closed'))
  ) THEN
    RAISE EXCEPTION 'invalid support case transition: % -> %', v_before.state, v_state;
  END IF;
  IF v_state <> v_before.state AND NOT EXISTS (
    SELECT 1 FROM growth.memberships m
     WHERE m.workspace_id = p_workspace_id
       AND m.user_id = growth.current_app_user_id()
       AND m.status = 'active' AND m.role IN ('owner','admin')
  ) THEN
    RAISE EXCEPTION 'support state management requires owner or admin';
  END IF;

  UPDATE growth.support_cases
     SET state = v_state, updated_by = growth.current_app_user_id(), updated_at = now()
   WHERE workspace_id = p_workspace_id AND id = p_case_id
   RETURNING * INTO v_after;
  INSERT INTO growth.support_case_events(
    workspace_id, support_case_id, actor_user_id, prior_state, new_state, note
  ) VALUES (
    p_workspace_id, p_case_id, growth.current_app_user_id(), v_before.state,
    v_after.state, btrim(p_note)
  );
  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION growth.list_latest_consents(p_workspace_id uuid)
RETURNS TABLE(
  consent_event_id uuid,
  managed_account_id uuid,
  consent_type text,
  decision text,
  policy_version text,
  effective_at timestamptz,
  actor_user_id uuid
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id) THEN
    RAISE EXCEPTION 'consent workspace context mismatch';
  END IF;
  RETURN QUERY
  SELECT DISTINCT ON (c.consent_type, c.managed_account_id)
         c.id, c.managed_account_id, c.consent_type, c.decision,
         c.policy_version, c.effective_at, c.actor_user_id
    FROM growth.consent_events c
   WHERE c.workspace_id = p_workspace_id
   ORDER BY c.consent_type, c.managed_account_id, c.effective_at DESC, c.id DESC;
END;
$$;

CREATE OR REPLACE FUNCTION growth.record_workspace_consent(
  p_workspace_id uuid,
  p_managed_account_id uuid,
  p_consent_type text,
  p_decision text,
  p_policy_version text
)
RETURNS growth.consent_events
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.consent_events;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
     OR p_consent_type NOT IN (
       'ai_processing','analytics_storage','aggregate_learning',
       'provider_data_processing','marketing_communications'
     )
     OR p_decision NOT IN ('granted','denied','revoked')
     OR length(btrim(coalesce(p_policy_version,''))) NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'consent event is invalid';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.memberships m
     WHERE m.workspace_id = p_workspace_id
       AND m.user_id = growth.current_app_user_id()
       AND m.status = 'active' AND m.role IN ('owner','admin')
  ) THEN
    RAISE EXCEPTION 'consent management requires owner or admin';
  END IF;
  IF p_managed_account_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM growth.managed_accounts a
     WHERE a.workspace_id = p_workspace_id AND a.id = p_managed_account_id
  ) THEN
    RAISE EXCEPTION 'managed account is unavailable';
  END IF;

  INSERT INTO growth.consent_events(
    id, workspace_id, managed_account_id, consent_type, decision,
    policy_version, effective_at, actor_user_id
  ) VALUES (
    gen_random_uuid(), p_workspace_id, p_managed_account_id, p_consent_type,
    p_decision, btrim(p_policy_version), now(), growth.current_app_user_id()
  ) RETURNING * INTO v_row;
  INSERT INTO growth.audit_events(
    id, workspace_id, actor_user_id, event_type, resource_type, resource_id, metadata
  ) VALUES (
    gen_random_uuid(), p_workspace_id, growth.current_app_user_id(),
    'privacy.consent.recorded', 'consent_event', v_row.id,
    jsonb_build_object('consent_type', p_consent_type, 'decision', p_decision,
                       'policy_version', btrim(p_policy_version))
  );
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION growth.list_deletion_requests(p_workspace_id uuid, p_limit integer DEFAULT 50)
RETURNS TABLE(
  id uuid,
  scope text,
  target_id uuid,
  state text,
  requested_by uuid,
  requested_at timestamptz,
  tombstoned_at timestamptz,
  completed_at timestamptz,
  manifest_version text,
  purge_jobs_total bigint,
  purge_jobs_confirmed bigint
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id) THEN
    RAISE EXCEPTION 'deletion workspace context mismatch';
  END IF;
  RETURN QUERY
  SELECT d.id, d.scope, d.target_id, d.state, d.requested_by, d.requested_at,
         d.tombstoned_at, d.completed_at, d.manifest_version,
         count(p.id), count(p.id) FILTER (WHERE p.state = 'confirmed')
    FROM growth.deletion_requests d
    LEFT JOIN growth.purge_jobs p
      ON p.workspace_id = d.workspace_id AND p.deletion_request_id = d.id
   WHERE d.workspace_id = p_workspace_id
   GROUP BY d.id
   ORDER BY d.requested_at DESC, d.id
   LIMIT greatest(1, least(coalesce(p_limit,50),100));
END;
$$;

CREATE OR REPLACE FUNCTION growth.create_deletion_request(
  p_workspace_id uuid,
  p_scope text,
  p_target_id uuid,
  p_manifest_version text
)
RETURNS growth.deletion_requests
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.deletion_requests;
  v_target_valid boolean := false;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
     OR p_scope NOT IN ('workspace','account','content','user')
     OR p_target_id IS NULL
     OR length(btrim(coalesce(p_manifest_version,''))) NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'deletion request is invalid';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.memberships m
     WHERE m.workspace_id = p_workspace_id
       AND m.user_id = growth.current_app_user_id()
       AND m.status = 'active' AND m.role IN ('owner','admin')
  ) THEN
    RAISE EXCEPTION 'deletion request requires owner or admin';
  END IF;

  IF p_scope = 'workspace' THEN
    v_target_valid := p_target_id = p_workspace_id;
  ELSIF p_scope = 'account' THEN
    SELECT EXISTS(SELECT 1 FROM growth.managed_accounts a
      WHERE a.workspace_id = p_workspace_id AND a.id = p_target_id) INTO v_target_valid;
  ELSIF p_scope = 'content' THEN
    SELECT EXISTS(SELECT 1 FROM growth.content_items c
      WHERE c.workspace_id = p_workspace_id AND c.id = p_target_id) INTO v_target_valid;
  ELSE
    SELECT EXISTS(SELECT 1 FROM growth.memberships m
      WHERE m.workspace_id = p_workspace_id AND m.user_id = p_target_id) INTO v_target_valid;
  END IF;
  IF NOT v_target_valid THEN RAISE EXCEPTION 'deletion target is unavailable'; END IF;

  INSERT INTO growth.deletion_requests(
    id, workspace_id, requested_by, scope, target_id, state, manifest_version
  ) VALUES (
    gen_random_uuid(), p_workspace_id, growth.current_app_user_id(), p_scope,
    p_target_id, 'requested', btrim(p_manifest_version)
  ) RETURNING * INTO v_row;
  INSERT INTO growth.audit_events(
    id, workspace_id, actor_user_id, event_type, resource_type, resource_id, metadata
  ) VALUES (
    gen_random_uuid(), p_workspace_id, growth.current_app_user_id(),
    'privacy.deletion.requested', 'deletion_request', v_row.id,
    jsonb_build_object('scope', p_scope, 'target_id', p_target_id,
                       'manifest_version', btrim(p_manifest_version))
  );
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION growth.tombstone_deletion_request(
  p_workspace_id uuid,
  p_request_id uuid
)
RETURNS growth.deletion_requests
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.deletion_requests;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id) THEN
    RAISE EXCEPTION 'deletion workspace context mismatch';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM growth.memberships m
     WHERE m.workspace_id = p_workspace_id
       AND m.user_id = growth.current_app_user_id()
       AND m.status = 'active' AND m.role IN ('owner','admin')
  ) THEN
    RAISE EXCEPTION 'deletion tombstone requires owner or admin';
  END IF;
  SELECT * INTO v_row FROM growth.deletion_requests d
   WHERE d.workspace_id = p_workspace_id AND d.id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_row.state <> 'requested' THEN
    RAISE EXCEPTION 'deletion request is not ready for tombstone';
  END IF;
  IF EXISTS (
    SELECT 1 FROM growth.deletion_tombstones t
     WHERE t.workspace_id = p_workspace_id
       AND t.target_type = v_row.scope
       AND t.target_id = v_row.target_id
  ) THEN
    RAISE EXCEPTION 'deletion target is already tombstoned';
  END IF;

  INSERT INTO growth.deletion_tombstones(
    workspace_id, target_type, target_id, deletion_request_id, effective_at
  ) VALUES (
    p_workspace_id, v_row.scope, v_row.target_id, v_row.id, now()
  );
  UPDATE growth.deletion_requests
     SET state = 'tombstoned'
   WHERE workspace_id = p_workspace_id AND id = p_request_id
   RETURNING * INTO v_row;
  INSERT INTO growth.audit_events(
    id, workspace_id, actor_user_id, event_type, resource_type, resource_id, metadata
  ) VALUES (
    gen_random_uuid(), p_workspace_id, growth.current_app_user_id(),
    'privacy.deletion.tombstoned', 'deletion_request', v_row.id,
    jsonb_build_object('scope', v_row.scope, 'target_id', v_row.target_id)
  );
  RETURN v_row;
END;
$$;

ALTER FUNCTION growth.list_agency_clients(uuid) OWNER TO growth_migrator;
ALTER FUNCTION growth.set_agency_client(uuid,uuid,text,text) OWNER TO growth_migrator;
ALTER FUNCTION growth.list_support_cases(uuid,integer) OWNER TO growth_migrator;
ALTER FUNCTION growth.create_support_case(uuid,text,text,text,text) OWNER TO growth_migrator;
ALTER FUNCTION growth.update_support_case(uuid,uuid,text,text) OWNER TO growth_migrator;
ALTER FUNCTION growth.list_latest_consents(uuid) OWNER TO growth_migrator;
ALTER FUNCTION growth.record_workspace_consent(uuid,uuid,text,text,text) OWNER TO growth_migrator;
ALTER FUNCTION growth.list_deletion_requests(uuid,integer) OWNER TO growth_migrator;
ALTER FUNCTION growth.create_deletion_request(uuid,text,uuid,text) OWNER TO growth_migrator;
ALTER FUNCTION growth.tombstone_deletion_request(uuid,uuid) OWNER TO growth_migrator;

REVOKE ALL ON FUNCTION growth.list_agency_clients(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.set_agency_client(uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.list_support_cases(uuid,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.create_support_case(uuid,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.update_support_case(uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.list_latest_consents(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.record_workspace_consent(uuid,uuid,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.list_deletion_requests(uuid,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.create_deletion_request(uuid,text,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.tombstone_deletion_request(uuid,uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION growth.list_agency_clients(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.set_agency_client(uuid,uuid,text,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.list_support_cases(uuid,integer) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.create_support_case(uuid,text,text,text,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.update_support_case(uuid,uuid,text,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.list_latest_consents(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.record_workspace_consent(uuid,uuid,text,text,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.list_deletion_requests(uuid,integer) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.create_deletion_request(uuid,text,uuid,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.tombstone_deletion_request(uuid,uuid) TO app_runtime;

COMMIT;
