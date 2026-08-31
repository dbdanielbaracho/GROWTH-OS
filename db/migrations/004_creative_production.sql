-- Growth OS — Creative Production forward migration.
--
-- Implements Especificação Técnica v0.5.2 CANDIDATA (RLS & Lineage Cycle
-- Hardening), frozen in db/CREATIVE_PRODUCTION_v0.5.2_FREEZE_RECORD.md.
-- RC9 (001, 002) and Post-RC9 Content (003) remain frozen and unmodified.
-- This file is a new, separately versioned evolution.
--
-- Every table introduced here is RLS-enabled and RLS-forced in the SAME
-- migration that creates it — not as a later patch. This directly closes
-- the v0.5.1 finding: the prototype that produced the earlier physical
-- proofs had no RLS on these three entities, so those proofs stood only
-- for business logic, never for tenant isolation. Grants are issued in a
-- separate provisioning file, applied only after this file (RLS +
-- policies) has already run.
--
-- EXECUTION IDENTITY: runs entirely as growth_migrator. No object created
-- here needs an ALTER OWNER to growth_rls_helper — none of the new
-- functions touch memberships or workspaces, so none of them carry the
-- recursion risk that made growth_rls_helper necessary in RC9.

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- ============================================================
-- creative_requests — the intention behind a generation, before it
-- exists. content_item_id/content_version_id are nullable (a request can
-- precede Content), but every request must declare a source_type +
-- source_id so it is never semantically orphaned. Reuses the typed loose
-- reference pattern already established by insight_evidence
-- (evidence_type + evidence_ref) rather than a rigid polymorphic FK,
-- since the referenced table varies by source_type. Existence/ownership
-- of source_id is validated by the application/service layer at request
-- creation time, not by a database FK — the target table is not fixed.
-- ============================================================
CREATE TABLE creative_requests (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  content_item_id uuid,
  content_version_id uuid,
  source_type text NOT NULL CHECK (source_type IN ('opportunity','insight','experiment','multiply','user_request','content')),
  source_id uuid NOT NULL,
  capability text NOT NULL,
  modality text NOT NULL CHECK (modality IN ('text','image','video','audio','embedding')),
  target_market text NOT NULL,
  target_language text NOT NULL,
  requested_by uuid NOT NULL REFERENCES users(id),
  status text NOT NULL CHECK (status IN ('requested','in_progress','completed','failed','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, id),
  FOREIGN KEY (workspace_id, content_item_id) REFERENCES content_items(workspace_id, id),
  FOREIGN KEY (workspace_id, content_version_id) REFERENCES content_versions(workspace_id, id)
);

ALTER TABLE creative_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE creative_requests FORCE ROW LEVEL SECURITY;

CREATE POLICY creative_requests_workspace_isolation ON creative_requests
  USING (workspace_id = current_workspace_id() AND tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = current_workspace_id() AND tenant_context_valid(workspace_id));

-- ============================================================
-- creative_generations — business lifecycle of one generation attempt.
-- Deliberately separate from growth.jobs, which stays as generic async
-- infrastructure (queued/leased/retry_wait/done/dead) and is not
-- modified by this migration. The relationship between the two is by
-- value (a job's payload carries a creative_generation_id), never by FK
-- — jobs is intentionally not tenant-scoped, and a real FK from a
-- tenant-scoped, RLS-forced table into a non-tenant-scoped one would
-- break the boundary RC9 already established deliberately.
-- ============================================================
CREATE TABLE creative_generations (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  creative_request_id uuid NOT NULL,
  provider text NOT NULL,
  model text,
  status text NOT NULL CHECK (status IN ('requested','queued','processing','succeeded','failed','cancelled','ambiguous')),
  attempts integer NOT NULL DEFAULT 0,
  supports_provider_idempotency boolean NOT NULL DEFAULT false,
  idempotency_key text NOT NULL,
  external_handle text,
  error_class text,
  error_detail jsonb,
  cost_amount numeric,
  currency text,
  units numeric,
  provenance jsonb,
  resolved_manually boolean NOT NULL DEFAULT false,
  resolved_by uuid REFERENCES users(id),
  resolved_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id, idempotency_key),
  FOREIGN KEY (workspace_id, creative_request_id) REFERENCES creative_requests(workspace_id, id)
);

ALTER TABLE creative_generations ENABLE ROW LEVEL SECURITY;
ALTER TABLE creative_generations FORCE ROW LEVEL SECURITY;

CREATE POLICY creative_generations_workspace_isolation ON creative_generations
  USING (workspace_id = current_workspace_id() AND tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = current_workspace_id() AND tenant_context_valid(workspace_id));

-- Full 42-transition allow-list, physically proven cell by cell before
-- this file was written. succeeded/failed/cancelled are terminal — a
-- retry after failed creates a new creative_generations row, the old one
-- is never reopened. ambiguous represents an unknown external outcome
-- (possible side effect, unknown result) and can only reconcile forward
-- to succeeded/failed, never blindly back to queued/processing — that
-- is the concrete mechanism that prevents a blind retry against a
-- provider that already may have started (and possibly charged for) the
-- generation.
CREATE OR REPLACE FUNCTION growth.creative_generation_transition_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  allowed boolean;
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW; -- other-column update, not a state transition
  END IF;

  SELECT (OLD.status, NEW.status) IN (
    ('requested','queued'), ('requested','cancelled'),
    ('queued','processing'), ('queued','cancelled'),
    ('processing','succeeded'), ('processing','failed'),
    ('processing','ambiguous'), ('processing','cancelled'),
    ('ambiguous','succeeded'), ('ambiguous','failed')
  ) INTO allowed;

  IF NOT allowed THEN
    RAISE EXCEPTION 'invalid creative_generation status transition: % -> %', OLD.status, NEW.status;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION growth.creative_generation_transition_guard() FROM PUBLIC;

CREATE TRIGGER creative_generations_transition_guard
BEFORE UPDATE ON creative_generations
FOR EACH ROW EXECUTE FUNCTION growth.creative_generation_transition_guard();

-- ============================================================
-- media_assets extensions — content_version_id is reserved for the
-- publishable output specific to that version (never shared as-is).
-- Reusable inputs (source/intermediate assets — voice clips, music,
-- stock avatars) stay content_version_id = NULL and are reachable only
-- through media_asset_lineage. Physically proven necessary: tying a
-- reused asset to one owning content_version_id makes it vanish via RLS
-- the moment that content's version is tombstoned, even while a second,
-- unrelated content still legitimately depends on it.
-- ============================================================
ALTER TABLE media_assets ADD COLUMN content_version_id uuid;
ALTER TABLE media_assets ADD COLUMN creative_generation_id uuid;
ALTER TABLE media_assets ADD COLUMN purpose text CHECK (purpose IN ('source','intermediate','publishable'));

ALTER TABLE media_assets ADD CONSTRAINT media_assets_content_version_fkey
  FOREIGN KEY (workspace_id, content_version_id) REFERENCES content_versions(workspace_id, id);
ALTER TABLE media_assets ADD CONSTRAINT media_assets_generation_fkey
  FOREIGN KEY (workspace_id, creative_generation_id) REFERENCES creative_generations(workspace_id, id);

-- Replaces the generic tenant_isolation-loop policy media_assets carried
-- since RC9 with a tombstone-aware one, matching content_approvals and
-- content_localizations from Post-RC9 Content: an asset whose own
-- content_version_id points at now-tombstoned content must become
-- invisible, exactly like content_items/content_versions themselves.
-- Assets with content_version_id IS NULL (reusable inputs) are governed
-- purely by the base tenant_context_valid() check — never automatically
-- hidden by any one content's deletion, since they are not owned by any
-- single content_version.
DROP POLICY media_assets_workspace_isolation ON media_assets;

CREATE POLICY media_assets_workspace_isolation ON media_assets
  USING (
    workspace_id = current_workspace_id()
    AND tenant_context_valid(workspace_id)
    AND (content_version_id IS NULL OR content_version_visible(workspace_id, content_version_id))
  )
  WITH CHECK (
    workspace_id = current_workspace_id()
    AND tenant_context_valid(workspace_id)
    AND (content_version_id IS NULL OR content_version_visible(workspace_id, content_version_id))
  );

-- ============================================================
-- media_asset_lineage — the composition/reuse graph (m:n). A direct FK
-- on media_assets answers "which content is this asset for" for the
-- common case; this edge table answers "what was this asset composed
-- from", supporting genuine reuse (the same input asset can be
-- input_asset_id for many different output_asset_id rows).
-- ============================================================
CREATE TABLE media_asset_lineage (
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  output_asset_id uuid NOT NULL,
  input_asset_id uuid NOT NULL,
  role text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workspace_id, output_asset_id, input_asset_id),
  CHECK (output_asset_id <> input_asset_id),
  FOREIGN KEY (workspace_id, output_asset_id) REFERENCES media_assets(workspace_id, id),
  FOREIGN KEY (workspace_id, input_asset_id) REFERENCES media_assets(workspace_id, id)
);

ALTER TABLE media_asset_lineage ENABLE ROW LEVEL SECURITY;
ALTER TABLE media_asset_lineage FORCE ROW LEVEL SECURITY;

CREATE POLICY media_asset_lineage_workspace_isolation ON media_asset_lineage
  USING (workspace_id = current_workspace_id() AND tenant_context_valid(workspace_id))
  WITH CHECK (workspace_id = current_workspace_id() AND tenant_context_valid(workspace_id));

-- Structural cycle rejection, generalizing RC9's reject_insight_demotion_cycle
-- (a single-linked-list check) to a general DAG with multiple inputs per
-- output. Serialized per workspace via advisory lock so a concurrent
-- insert cannot race past the check before the other transaction
-- commits — physically proven with two real concurrent sessions before
-- this file was written: the second session, blocked until the first
-- committed, correctly detected and rejected the resulting cycle.
-- Not SECURITY DEFINER: only queries media_asset_lineage itself, which
-- the caller already has direct access to — no recursion risk, no
-- elevated privilege needed.
CREATE OR REPLACE FUNCTION growth.reject_media_asset_lineage_cycle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, growth
AS $$
DECLARE
  cycle_found boolean;
BEGIN
  IF NEW.output_asset_id = NEW.input_asset_id THEN
    RAISE EXCEPTION 'media_asset_lineage cannot self-reference';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(NEW.workspace_id::text || ':media_asset_lineage'));

  WITH RECURSIVE downstream(asset_id, path) AS (
    SELECT NEW.output_asset_id, ARRAY[NEW.output_asset_id]
    UNION ALL
    SELECT mal.output_asset_id, d.path || mal.output_asset_id
    FROM growth.media_asset_lineage mal
    JOIN downstream d ON mal.input_asset_id = d.asset_id
    WHERE mal.workspace_id = NEW.workspace_id
      AND NOT mal.output_asset_id = ANY(d.path)
  )
  SELECT EXISTS (SELECT 1 FROM downstream WHERE asset_id = NEW.input_asset_id) INTO cycle_found;

  IF cycle_found THEN
    RAISE EXCEPTION 'media_asset_lineage edge would create a cycle: % already reaches %', NEW.output_asset_id, NEW.input_asset_id;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION growth.reject_media_asset_lineage_cycle() FROM PUBLIC;

CREATE TRIGGER media_asset_lineage_reject_cycle
BEFORE INSERT ON media_asset_lineage
FOR EACH ROW EXECUTE FUNCTION growth.reject_media_asset_lineage_cycle();
