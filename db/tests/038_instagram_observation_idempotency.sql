-- Instagram observation idempotency regression gate.
-- Verifies both the stable-field contract and the runtime conflict behavior.
\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  fn regprocedure := 'growth.instagram_record_metric_observation(uuid,text,text,numeric,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,timestamp with time zone,text,text,uuid,text,text,text,text)'::regprocedure;
  def text;
  required_fragment text;
  workspace_id uuid := 'b0000000-0000-4000-8000-000000000001';
  user_id uuid := 'a0000000-0000-4000-8000-000000000001';
  managed_id uuid := 'c0000000-0000-4000-8000-000000000901';
  authority_id uuid := 'c0000000-0000-4000-8000-000000000902';
  connection_id uuid := 'c0000000-0000-4000-8000-000000000903';
  social_id uuid := 'c0000000-0000-4000-8000-000000000904';
  collection_run_id uuid := 'c0000000-0000-4000-8000-000000000905';
  first_id uuid;
  second_id uuid;
  conflict_seen boolean := false;
BEGIN
  SELECT pg_get_functiondef(fn) INTO def;

  IF def IS NULL OR position('IS NOT DISTINCT FROM' in def)=0 THEN
    RAISE EXCEPTION '038 failed: idempotency comparison must be NULL-safe';
  END IF;

  FOREACH required_fragment IN ARRAY ARRAY[
    'existing.social_account_id',
    'existing.provider_content_id',
    'existing.metric_name',
    'existing.raw_value',
    'existing.unit',
    'existing.observed_at',
    'existing.provider_effective_at',
    'existing.provider_api_version',
    'existing.source_schema_version',
    'existing.collection_method',
    'existing.raw_payload_ref',
    'existing.adapter_version',
    'existing.provider_product',
    'existing.provider_object_type',
    'existing.metric_semantic_version',
    'existing.semantic_effective_from',
    'existing.semantic_effective_to',
    'existing.source_range_start',
    'existing.source_range_end',
    'existing.authorization_class',
    'existing.completeness_status',
    'existing.freshness_status',
    'existing.collection_run_id'
  ] LOOP
    IF position(required_fragment in def)=0 THEN
      RAISE EXCEPTION '038 failed: stable idempotency field missing: %', required_fragment;
    END IF;
  END LOOP;

  IF has_function_privilege('public',fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '038 failed: PUBLIC can execute Instagram observation helper';
  END IF;

  IF NOT has_function_privilege('app_runtime',fn::text,'EXECUTE') THEN
    RAISE EXCEPTION '038 failed: app_runtime lost required helper EXECUTE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid=fn
      AND pg_get_userbyid(p.proowner)='growth_migrator'
      AND p.prosecdef
  ) THEN
    RAISE EXCEPTION '038 failed: helper ownership/security boundary changed';
  END IF;

  SELECT set_config('app.workspace_id',workspace_id::text,true);
  SELECT set_config('app.user_id',user_id::text,true);

  INSERT INTO growth.managed_accounts(
    id,workspace_id,owner_type,authority_status,contribution_eligibility,authority_clause_ref
  ) VALUES (
    managed_id,workspace_id,'direct','contractually_granted','eligible','test-fixture'
  );

  INSERT INTO growth.authority_history(
    id,workspace_id,managed_account_id,owner_type,authority_status,
    contribution_eligibility,authority_clause_ref,effective_from,effective_to
  ) VALUES (
    authority_id,workspace_id,managed_id,'direct','contractually_granted',
    'eligible','test-fixture','2026-09-01T00:00:00Z'::timestamptz,NULL
  );

  INSERT INTO growth.platform_connections(
    id,workspace_id,managed_account_id,platform,state
  ) VALUES (
    connection_id,workspace_id,managed_id,'instagram','connected'
  );

  INSERT INTO growth.social_accounts(
    id,workspace_id,managed_account_id,platform_connection_id,platform,
    provider_account_id,handle,account_type,market,timezone
  ) VALUES (
    social_id,workspace_id,managed_id,connection_id,'instagram',
    'instagram-idempotency-gate','@idempotency-gate','business','US','UTC'
  );

  SET LOCAL ROLE app_runtime;

  SELECT growth.instagram_record_metric_observation(
    social_id,'media:idempotency-gate','like_count',120,'seconds',
    '2026-09-06T00:00:00Z'::timestamptz,
    '2026-09-06T00:00:00Z'::timestamptz,
    'UTC','v24.0','instagram.media.v1','instagram','media',
    'instagram.metrics.v1','2026-09-01T00:00:00Z'::timestamptz,NULL,
    NULL,NULL,'2026-09-06T00:01:00Z'::timestamptz,
    'authorized_account','2026-10-06T00:01:00Z'::timestamptz,
    '2026-10-05T00:01:00Z'::timestamptz,'complete','fresh',
    collection_run_id,'idem-instagram-unit-regression','sha256:instagram-gate',
    'instagram-v0.2','polling'
  ) INTO first_id;

  SELECT growth.instagram_record_metric_observation(
    social_id,'media:idempotency-gate','like_count',120,'seconds',
    '2026-09-06T00:00:00Z'::timestamptz,
    '2026-09-06T00:00:00Z'::timestamptz,
    'UTC','v24.0','instagram.media.v1','instagram','media',
    'instagram.metrics.v1','2026-09-01T00:00:00Z'::timestamptz,NULL,
    NULL,NULL,'2026-09-06T00:01:00Z'::timestamptz,
    'authorized_account','2026-10-06T00:01:00Z'::timestamptz,
    '2026-10-05T00:01:00Z'::timestamptz,'complete','fresh',
    collection_run_id,'idem-instagram-unit-regression','sha256:instagram-gate',
    'instagram-v0.2','polling'
  ) INTO second_id;

  IF first_id IS NULL OR second_id IS DISTINCT FROM first_id THEN
    RAISE EXCEPTION '038 failed: identical retry was not idempotent';
  END IF;

  BEGIN
    PERFORM growth.instagram_record_metric_observation(
      social_id,'media:idempotency-gate','like_count',120,'minutes',
      '2026-09-06T00:00:00Z'::timestamptz,
      '2026-09-06T00:00:00Z'::timestamptz,
      'UTC','v24.0','instagram.media.v1','instagram','media',
      'instagram.metrics.v1','2026-09-01T00:00:00Z'::timestamptz,NULL,
      NULL,NULL,'2026-09-06T00:01:00Z'::timestamptz,
      'authorized_account','2026-10-06T00:01:00Z'::timestamptz,
      '2026-10-05T00:01:00Z'::timestamptz,'complete','fresh',
      collection_run_id,'idem-instagram-unit-regression','sha256:instagram-gate',
      'instagram-v0.2','polling'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'instagram observation idempotency conflict' THEN
      RAISE EXCEPTION '038 failed: unexpected conflict error: %', SQLERRM;
    END IF;
    conflict_seen := true;
  END;

  IF NOT conflict_seen THEN
    RAISE EXCEPTION '038 failed: changed unit was silently accepted under same idempotency key';
  END IF;
END $$;

ROLLBACK;

\echo 'PASS 038_instagram_observation_idempotency'
