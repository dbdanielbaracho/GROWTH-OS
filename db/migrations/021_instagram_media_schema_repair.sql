-- Growth OS — repair of the Instagram media foundation after production drift.
-- Forward-only migration. Preserves 019/020 and restores only missing objects.
-- No data is deleted or rewritten.

\set ON_ERROR_STOP on

BEGIN;

SET search_path = growth, public;

DO $$
BEGIN
  IF to_regclass('growth.instagram_media') IS NULL THEN
    RAISE EXCEPTION '021 requires growth.instagram_media from migration 019';
  END IF;
END
$$;

ALTER TABLE growth.instagram_media OWNER TO growth_migrator;
ALTER TABLE growth.instagram_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.instagram_media FORCE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname='growth'
      AND tablename='instagram_media'
      AND policyname='instagram_media_workspace_isolation'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY instagram_media_workspace_isolation
        ON growth.instagram_media
        USING (
          workspace_id = growth.current_workspace_id()
          AND growth.tenant_context_valid(workspace_id)
        )
        WITH CHECK (
          workspace_id = growth.current_workspace_id()
          AND growth.tenant_context_valid(workspace_id)
        )
    $policy$;
  ELSE
    EXECUTE $policy$
      ALTER POLICY instagram_media_workspace_isolation
        ON growth.instagram_media
        USING (
          workspace_id = growth.current_workspace_id()
          AND growth.tenant_context_valid(workspace_id)
        )
        WITH CHECK (
          workspace_id = growth.current_workspace_id()
          AND growth.tenant_context_valid(workspace_id)
        )
    $policy$;
  END IF;
END
$$;

REVOKE ALL ON TABLE growth.instagram_media FROM PUBLIC;
REVOKE ALL ON TABLE growth.instagram_media FROM app_runtime;

CREATE INDEX IF NOT EXISTS instagram_media_account_posted_idx
  ON growth.instagram_media(workspace_id, social_account_id, posted_at DESC);

CREATE OR REPLACE FUNCTION growth.instagram_record_media(
  p_social_account_id uuid,
  p_provider_media_id text,
  p_media_type text,
  p_media_product_type text,
  p_permalink text,
  p_caption text,
  p_posted_at timestamptz,
  p_media_url text,
  p_thumbnail_url text,
  p_collected_at timestamptz,
  p_raw_payload_ref text,
  p_adapter_version text
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ws uuid := growth.current_workspace_id();
  existing_id uuid;
  existing_account uuid;
  media_id uuid := gen_random_uuid();
BEGIN
  IF ws IS NULL OR growth.current_app_user_id() IS NULL OR NOT growth.tenant_context_valid(ws) THEN
    RAISE EXCEPTION 'instagram media requires active tenant context';
  END IF;
  IF btrim(coalesce(p_provider_media_id,'')) = ''
     OR btrim(coalesce(p_media_type,'')) = ''
     OR btrim(coalesce(p_raw_payload_ref,'')) = ''
     OR btrim(coalesce(p_adapter_version,'')) = ''
     OR p_collected_at IS NULL THEN
    RAISE EXCEPTION 'instagram media provenance contract is incomplete';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM growth.social_accounts sa
    JOIN growth.platform_connections pc
      ON pc.workspace_id=sa.workspace_id AND pc.id=sa.platform_connection_id
    JOIN growth.managed_accounts ma
      ON ma.workspace_id=sa.workspace_id AND ma.id=sa.managed_account_id
    WHERE sa.workspace_id=ws
      AND sa.id=p_social_account_id
      AND sa.platform='instagram'
      AND pc.platform='instagram'
      AND pc.state='connected'
      AND ma.authority_status='contractually_granted'
  ) THEN
    RAISE EXCEPTION 'instagram media requires connected authorized account';
  END IF;

  SELECT im.id, im.social_account_id
    INTO existing_id, existing_account
  FROM growth.instagram_media im
  WHERE im.workspace_id=ws
    AND im.provider_media_id=p_provider_media_id
  FOR UPDATE;

  IF existing_id IS NOT NULL AND existing_account <> p_social_account_id THEN
    RAISE EXCEPTION 'instagram media belongs to another social account';
  END IF;

  IF existing_id IS NULL THEN
    INSERT INTO growth.instagram_media(
      id,workspace_id,social_account_id,provider_media_id,media_type,
      media_product_type,permalink,caption,posted_at,media_url,thumbnail_url,
      collected_at,raw_payload_ref,adapter_version,created_at,updated_at
    )
    VALUES(
      media_id,ws,p_social_account_id,p_provider_media_id,p_media_type,
      nullif(btrim(coalesce(p_media_product_type,'')), ''),
      nullif(btrim(coalesce(p_permalink,'')), ''),
      p_caption,p_posted_at,p_media_url,p_thumbnail_url,
      p_collected_at,p_raw_payload_ref,p_adapter_version,now(),now()
    );
    RETURN media_id;
  END IF;

  UPDATE growth.instagram_media
  SET media_type=p_media_type,
      media_product_type=nullif(btrim(coalesce(p_media_product_type,'')), ''),
      permalink=nullif(btrim(coalesce(p_permalink,'')), ''),
      caption=p_caption,
      posted_at=p_posted_at,
      media_url=p_media_url,
      thumbnail_url=p_thumbnail_url,
      collected_at=p_collected_at,
      raw_payload_ref=p_raw_payload_ref,
      adapter_version=p_adapter_version,
      updated_at=now()
  WHERE workspace_id=ws AND id=existing_id;

  RETURN existing_id;
END;
$$;

ALTER FUNCTION growth.instagram_record_media(uuid,text,text,text,text,text,timestamptz,text,text,timestamptz,text,text)
  OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.instagram_record_media(uuid,text,text,text,text,text,timestamptz,text,text,timestamptz,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.instagram_record_media(uuid,text,text,text,text,text,timestamptz,text,text,timestamptz,text,text) TO app_runtime;

COMMIT;
