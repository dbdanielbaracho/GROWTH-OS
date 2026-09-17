-- Growth OS — explicit, auditable content submission for review.
-- Forward-only migration 065.

BEGIN;
SET search_path = growth, public;

CREATE TABLE growth.content_review_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  content_version_id uuid NOT NULL,
  actor_user_id uuid NOT NULL REFERENCES growth.users(id),
  note text,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, id),
  FOREIGN KEY (workspace_id, content_version_id)
    REFERENCES growth.content_versions(workspace_id, id),
  CONSTRAINT content_review_submission_note_length
    CHECK (note IS NULL OR char_length(note) <= 1000)
);

CREATE INDEX content_review_submissions_version_idx
  ON growth.content_review_submissions(workspace_id, content_version_id, submitted_at DESC);

ALTER TABLE growth.content_review_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.content_review_submissions FORCE ROW LEVEL SECURITY;
CREATE POLICY content_review_submissions_workspace_isolation
  ON growth.content_review_submissions
  USING (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
  )
  WITH CHECK (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
  );

ALTER TABLE growth.content_review_submissions OWNER TO growth_migrator;
REVOKE ALL ON TABLE growth.content_review_submissions FROM PUBLIC;
REVOKE ALL ON TABLE growth.content_review_submissions FROM app_runtime;

-- Saving a new version is editing, not an approval request. Keep the item as
-- a draft so every transition into review is explicit and audit-backed.
CREATE OR REPLACE FUNCTION growth.content_new_version(
  p_workspace_id uuid, p_content_item_id uuid, p_body text, p_checksum text,
  p_structure jsonb DEFAULT '{}'::jsonb, p_ai_provenance jsonb DEFAULT NULL
)
RETURNS growth.content_versions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $content_new_version$
DECLARE
  v_next_version_no integer;
  v_row growth.content_versions;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'content version workspace context mismatch';
  END IF;

  PERFORM 1
    FROM growth.content_items
   WHERE workspace_id = p_workspace_id
     AND id = p_content_item_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'content_item not found or not visible in this tenant context';
  END IF;

  SELECT COALESCE(MAX(version_no), 0) + 1
    INTO v_next_version_no
    FROM growth.content_versions
   WHERE workspace_id = p_workspace_id
     AND content_item_id = p_content_item_id;

  INSERT INTO growth.content_versions(
    id, workspace_id, content_item_id, version_no, body,
    structure_json, ai_provenance, checksum
  )
  VALUES (
    gen_random_uuid(), p_workspace_id, p_content_item_id, v_next_version_no,
    p_body, p_structure, p_ai_provenance, p_checksum
  )
  RETURNING * INTO v_row;

  UPDATE growth.content_items
     SET status = 'draft'
   WHERE workspace_id = p_workspace_id
     AND id = p_content_item_id;

  RETURN v_row;
END;
$content_new_version$;

CREATE OR REPLACE FUNCTION growth.content_submit_for_review(
  p_workspace_id uuid,
  p_content_version_id uuid,
  p_note text DEFAULT NULL
)
RETURNS growth.content_review_submissions
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $content_submit_for_review$
DECLARE
  v_item_id uuid;
  v_current_status text;
  v_row growth.content_review_submissions;
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'content review workspace context mismatch';
  END IF;
  IF p_note IS NOT NULL AND char_length(p_note) > 1000 THEN
    RAISE EXCEPTION 'content review note is too long';
  END IF;

  SELECT cv.content_item_id
    INTO v_item_id
    FROM growth.content_versions cv
   WHERE cv.workspace_id = p_workspace_id
     AND cv.id = p_content_version_id
     AND NOT EXISTS (
       SELECT 1
         FROM growth.content_versions newer
        WHERE newer.workspace_id = cv.workspace_id
          AND newer.content_item_id = cv.content_item_id
          AND newer.version_no > cv.version_no
     );

  IF v_item_id IS NULL THEN
    RAISE EXCEPTION 'latest content version not found in this workspace';
  END IF;

  SELECT ci.status
    INTO v_current_status
    FROM growth.content_items ci
   WHERE ci.workspace_id = p_workspace_id
     AND ci.id = v_item_id
   FOR UPDATE;

  IF v_current_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'cannot submit content from status %, expected draft', v_current_status;
  END IF;

  INSERT INTO growth.content_review_submissions (
    workspace_id, content_version_id, actor_user_id, note
  ) VALUES (
    p_workspace_id,
    p_content_version_id,
    growth.current_app_user_id(),
    nullif(trim(p_note), '')
  )
  RETURNING * INTO v_row;

  UPDATE growth.content_items
     SET status = 'ready_for_review'
   WHERE workspace_id = p_workspace_id
     AND id = v_item_id;

  RETURN v_row;
END;
$content_submit_for_review$;

ALTER FUNCTION growth.content_submit_for_review(uuid,uuid,text) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.content_submit_for_review(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.content_submit_for_review(uuid,uuid,text) TO app_runtime;

COMMIT;
