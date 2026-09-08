-- Growth OS — controlled publication intent foundation.
-- Creates an auditable, approval-gated intent only. No provider call occurs here.

\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

CREATE OR REPLACE FUNCTION growth.create_publication_intent(
  p_workspace_id uuid,
  p_social_account_id uuid,
  p_content_version_id uuid,
  p_request_nonce uuid,
  p_idempotency_key text
)
RETURNS growth.publication_intents
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_row growth.publication_intents;
  v_item_status text;
BEGIN
  IF p_workspace_id IS NULL
     OR p_social_account_id IS NULL
     OR p_content_version_id IS NULL
     OR p_request_nonce IS NULL
     OR p_idempotency_key IS NULL
     OR length(trim(p_idempotency_key)) = 0
  THEN
    RAISE EXCEPTION 'publication intent requires complete identifiers';
  END IF;

  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.tenant_context_valid(p_workspace_id)
  THEN
    RAISE EXCEPTION 'publication intent requires active tenant context';
  END IF;

  SELECT pi.* INTO v_row
  FROM growth.publication_intents pi
  WHERE pi.workspace_id = p_workspace_id
    AND pi.idempotency_key = p_idempotency_key;

  IF FOUND THEN
    IF v_row.social_account_id IS DISTINCT FROM p_social_account_id
       OR v_row.content_version_id IS DISTINCT FROM p_content_version_id
    THEN
      RAISE EXCEPTION 'idempotency key conflicts with another publication intent';
    END IF;
    RETURN v_row;
  END IF;

  SELECT ci.status INTO v_item_status
  FROM growth.content_versions cv
  JOIN growth.content_items ci
    ON ci.workspace_id = cv.workspace_id
   AND ci.id = cv.content_item_id
  WHERE cv.workspace_id = p_workspace_id
    AND cv.id = p_content_version_id
  FOR UPDATE OF ci, cv;

  IF v_item_status IS NULL THEN
    RAISE EXCEPTION 'content version not found or not visible in this tenant context';
  END IF;
  IF v_item_status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'only approved content can create a publication intent';
  END IF;

  PERFORM 1
  FROM growth.social_accounts sa
  JOIN growth.platform_connections pc
    ON pc.workspace_id = sa.workspace_id
   AND pc.id = sa.platform_connection_id
  WHERE sa.workspace_id = p_workspace_id
    AND sa.id = p_social_account_id
    AND pc.state = 'connected'
  FOR UPDATE OF sa, pc;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'publication requires a connected social account';
  END IF;

  INSERT INTO growth.publication_intents(
    id, workspace_id, social_account_id, content_version_id,
    request_nonce, idempotency_key, status
  )
  VALUES (
    gen_random_uuid(), p_workspace_id, p_social_account_id, p_content_version_id,
    p_request_nonce, p_idempotency_key, 'ready'
  )
  ON CONFLICT (workspace_id, idempotency_key) DO NOTHING
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    SELECT pi.* INTO v_row
    FROM growth.publication_intents pi
    WHERE pi.workspace_id = p_workspace_id
      AND pi.idempotency_key = p_idempotency_key;
  END IF;

  RETURN v_row;
END;
$$;

ALTER FUNCTION growth.create_publication_intent(uuid,uuid,uuid,uuid,text) OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.create_publication_intent(uuid,uuid,uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.create_publication_intent(uuid,uuid,uuid,uuid,text) TO app_runtime;

COMMIT;
