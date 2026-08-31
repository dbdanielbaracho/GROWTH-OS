-- Growth OS — Post-RC9 Content Domain Reconciliation (forward migration).
--
-- RC9 (db/migrations/001_initial_schema.sql +
-- db/migrations/002_rc9_security_policy_fix.sql) remains frozen and
-- unmodified — SHA-256 of 001 is still
-- b2bf18fc540bb08a0e0c17c911d91e91e9eda9d7504fa8120d5f9374eeb48b76.
-- This file is a new, separately versioned evolution, per the RC9 Freeze
-- Record: "any change to schema, RLS, roles, grants... requires a new
-- change record and a version subsequent to RC9."
--
-- Origin: reconciling docs/CONTENT_AUTHORING_V0.1.md and the RC9 schema
-- against Growth OS Especificação Técnica v0.4.1 CONGELADA, Section 10
-- (Content Domain), found two entities the frozen technical spec requires
-- that RC9 does not have (approval, localization), and two field-level
-- gaps in tables RC9 already has (media_asset duration/dimensions,
-- content_variant.variant_type).
--
-- EXECUTION IDENTITY: growth_migrator already owns every object this file
-- creates or alters (all pre-existing tables it modifies, and every new
-- object it creates) — no ALTER OWNER to growth_rls_helper is needed here,
-- unlike 002_rc9_security_policy_fix.sql. This file runs entirely as
-- growth_migrator.

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- ============================================================
-- Field-level gaps in existing RC9 tables.
-- ============================================================
ALTER TABLE media_assets ADD COLUMN duration_seconds numeric;
ALTER TABLE media_assets ADD COLUMN width_px integer;
ALTER TABLE media_assets ADD COLUMN height_px integer;

ALTER TABLE content_variants ADD COLUMN variant_type text;

-- content_items.status gains a real lifecycle. Existing rows (all 'draft'
-- from the current application) remain valid under this CHECK.
ALTER TABLE content_items ADD CONSTRAINT content_items_status_check
  CHECK (status IN ('draft','ready_for_review','approved'));

-- ============================================================
-- content_approvals — append-only decision history per content_version.
-- decision_no is assigned by trigger under an advisory lock keyed on
-- content_version_id, reflecting commit order (not allocation order):
-- a concurrent second submission physically waits for the first to
-- commit before it can even compute its own next number. Physically
-- proven with two real concurrent sessions before this migration was
-- written (decision_no 1 then 2, no duplicates, UNIQUE enforced).
-- ============================================================
CREATE TABLE content_approvals (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  content_version_id uuid NOT NULL,
  actor_user_id uuid NOT NULL REFERENCES users(id),
  decision text NOT NULL CHECK (decision IN ('approved','changes_requested')),
  decision_no integer NOT NULL CHECK (decision_no > 0),
  notes text,
  decided_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, content_version_id, decision_no),
  FOREIGN KEY (workspace_id, content_version_id)
    REFERENCES content_versions(workspace_id, id)
);

CREATE OR REPLACE FUNCTION growth.content_approval_assign_decision_no()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  hex text := replace(NEW.content_version_id::text, '-', '');
  k1 integer;
  k2 integer;
  next_no integer;
BEGIN
  k1 := ('x' || substr(hex,1,8))::bit(32)::integer;
  k2 := ('x' || substr(hex,9,8))::bit(32)::integer;
  PERFORM pg_advisory_xact_lock(k1,k2);

  SELECT COALESCE(MAX(decision_no), 0) + 1 INTO next_no
  FROM growth.content_approvals
  WHERE workspace_id = NEW.workspace_id AND content_version_id = NEW.content_version_id;

  NEW.decision_no := next_no;
  RETURN NEW;
END;
$$;

CREATE TRIGGER content_approvals_assign_decision_no
BEFORE INSERT ON content_approvals
FOR EACH ROW EXECUTE FUNCTION growth.content_approval_assign_decision_no();

-- ============================================================
-- content_localizations — links a source content_version to a localized
-- one. target_market/target_language are deliberately NOT stored here:
-- they are derived by joining to the content_item behind
-- localized_content_version_id, which already carries them as required
-- (NOT NULL) fields. Avoids a second, driftable copy of the same fact.
-- Trade-off (recorded, not hidden): this requires the localized
-- content_version to already exist when the row is created — there is no
-- "pending localization request" state in this design. No evidence in
-- the frozen conceptual/technical documents requires that state for
-- Release 1; a future migration can add it if needed.
-- ============================================================
CREATE TABLE content_localizations (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  source_content_version_id uuid NOT NULL,
  localized_content_version_id uuid NOT NULL,
  adaptation_notes text,
  ai_provenance jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (source_content_version_id <> localized_content_version_id),
  UNIQUE (workspace_id, id),
  UNIQUE (source_content_version_id, localized_content_version_id),
  FOREIGN KEY (workspace_id, source_content_version_id)
    REFERENCES content_versions(workspace_id, id),
  FOREIGN KEY (workspace_id, localized_content_version_id)
    REFERENCES content_versions(workspace_id, id)
);

-- ============================================================
-- content_version_visible — NOT SECURITY DEFINER: only queries
-- content_versions and deletion_tombstones, both of which app_runtime
-- already has direct SELECT on. Zero recursion risk (unlike the
-- memberships/workspaces fix in 002_rc9_security_policy_fix.sql), so no
-- growth_rls_helper involvement is needed here.
--
-- Physically proven necessary: without this check, an approval or
-- localization referencing a since-tombstoned content_item remained
-- visible via RLS even after content_items/content_versions themselves
-- correctly hid it — a dangling-reference leak, reproduced and fixed
-- before this migration was written.
-- ============================================================
CREATE OR REPLACE FUNCTION growth.content_version_visible(p_workspace_id uuid, p_content_version_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM growth.content_versions cv
    WHERE cv.workspace_id = p_workspace_id
      AND cv.id = p_content_version_id
      AND NOT EXISTS (
        SELECT 1 FROM growth.deletion_tombstones dt
        WHERE dt.workspace_id = cv.workspace_id
          AND dt.target_type = 'content'
          AND dt.target_id = cv.content_item_id
          AND dt.effective_at <= now()
      )
  );
$$;

ALTER TABLE content_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_approvals FORCE ROW LEVEL SECURITY;
ALTER TABLE content_localizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_localizations FORCE ROW LEVEL SECURITY;

CREATE POLICY content_approvals_workspace_isolation ON content_approvals
  USING (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
    AND growth.content_version_visible(workspace_id, content_version_id)
  )
  WITH CHECK (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
    AND growth.content_version_visible(workspace_id, content_version_id)
  );

CREATE POLICY content_localizations_workspace_isolation ON content_localizations
  USING (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
    AND growth.content_version_visible(workspace_id, source_content_version_id)
    AND growth.content_version_visible(workspace_id, localized_content_version_id)
  )
  WITH CHECK (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
    AND growth.content_version_visible(workspace_id, source_content_version_id)
    AND growth.content_version_visible(workspace_id, localized_content_version_id)
  );
