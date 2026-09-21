-- YouTube user-controlled revocation and same-channel reconnect gate.
\set ON_ERROR_STOP on

BEGIN;

DO $contract$
DECLARE
  revoke_oid oid := to_regprocedure('growth.youtube_revoke_connection(uuid)');
  update_oid oid := to_regprocedure('growth.youtube_update_connection_credential(uuid,bytea,text,text,timestamptz,boolean,text[])');
  owner_name text;
  is_definer boolean;
BEGIN
  IF revoke_oid IS NULL OR update_oid IS NULL THEN
    RAISE EXCEPTION '073 failed: YouTube revoke/reconnect helpers are missing';
  END IF;

  SELECT r.rolname, p.prosecdef INTO owner_name, is_definer
    FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
   WHERE p.oid = revoke_oid;
  IF owner_name <> 'growth_migrator'
     OR is_definer IS DISTINCT FROM true
     OR has_function_privilege('app_runtime', revoke_oid, 'EXECUTE') IS DISTINCT FROM true
     OR has_function_privilege('public', revoke_oid, 'EXECUTE') IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '073 failed: YouTube revoke helper privilege boundary';
  END IF;

  SELECT r.rolname, p.prosecdef INTO owner_name, is_definer
    FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
   WHERE p.oid = update_oid;
  IF owner_name <> 'growth_migrator'
     OR is_definer IS DISTINCT FROM true
     OR has_function_privilege('app_runtime', update_oid, 'EXECUTE') IS DISTINCT FROM true
     OR has_function_privilege('public', update_oid, 'EXECUTE') IS DISTINCT FROM false
  THEN
    RAISE EXCEPTION '073 failed: YouTube reconnect helper privilege boundary';
  END IF;
END;
$contract$;

SELECT set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
SELECT set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);

INSERT INTO growth.managed_accounts(
  id, workspace_id, owner_type, authority_status, contribution_eligibility, authority_clause_ref
) VALUES (
  'c0000000-0000-4000-8000-000000000731',
  'b0000000-0000-4000-8000-000000000001',
  'direct', 'contractually_granted', 'eligible', 'youtube-revocation-test-v1'
);

INSERT INTO growth.authority_history(
  id, workspace_id, managed_account_id, owner_type, authority_status,
  contribution_eligibility, authority_clause_ref, effective_from
) VALUES (
  'c0000000-0000-4000-8000-000000000732',
  'b0000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000731',
  'direct', 'contractually_granted', 'eligible', 'youtube-revocation-test-v1', now()
);

INSERT INTO growth.platform_connections(
  id, workspace_id, managed_account_id, platform, state, granted_scopes, token_expires_at
) VALUES (
  'c0000000-0000-4000-8000-000000000733',
  'b0000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000731',
  'youtube', 'connected',
  ARRAY['https://www.googleapis.com/auth/youtube.readonly','https://www.googleapis.com/auth/yt-analytics.readonly'],
  now() + interval '1 hour'
);

INSERT INTO growth.social_accounts(
  id, workspace_id, managed_account_id, platform_connection_id, platform,
  provider_account_id, handle, account_type, market, timezone
) VALUES (
  'c0000000-0000-4000-8000-000000000734',
  'b0000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000731',
  'c0000000-0000-4000-8000-000000000733',
  'youtube', 'youtube-channel-073', '@youtube-073', 'channel', 'US', 'America/Los_Angeles'
);

INSERT INTO growth.provider_credentials(
  workspace_id, platform_connection_id, provider, credential_ciphertext,
  cipher_version, key_version, token_expires_at, refresh_available
) VALUES (
  'b0000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000733',
  'youtube', decode('deadbeef', 'hex'), 'aes-256-gcm.v1', 'v1', now() + interval '1 hour', true
);

SET LOCAL ROLE app_runtime;

DO $runtime_revoke$
BEGIN
  IF growth.youtube_revoke_connection('c0000000-0000-4000-8000-000000000733') IS DISTINCT FROM true THEN
    RAISE EXCEPTION '073 failed: authorized runtime revocation was rejected';
  END IF;
  IF growth.youtube_revoke_connection('c0000000-0000-4000-8000-000000000739') IS DISTINCT FROM false THEN
    RAISE EXCEPTION '073 failed: unknown connection did not fail closed';
  END IF;
END;
$runtime_revoke$;

RESET ROLE;

DO $revoked_state$
DECLARE
  actual_state text;
  actual_error text;
  actual_scopes text[];
  credential_count integer;
BEGIN
  SELECT state, error_class, granted_scopes
    INTO actual_state, actual_error, actual_scopes
    FROM growth.platform_connections
   WHERE id = 'c0000000-0000-4000-8000-000000000733';
  SELECT count(*) INTO credential_count
    FROM growth.provider_credentials
   WHERE platform_connection_id = 'c0000000-0000-4000-8000-000000000733';

  IF actual_state <> 'revoked'
     OR actual_error <> 'youtube_user_revoked'
     OR cardinality(actual_scopes) <> 0
     OR credential_count <> 0
  THEN
    RAISE EXCEPTION '073 failed: revocation did not remove credential and clear connection state';
  END IF;
END;
$revoked_state$;

SET LOCAL ROLE app_runtime;

DO $runtime_reconnect$
BEGIN
  IF growth.youtube_update_connection_credential(
    'c0000000-0000-4000-8000-000000000733',
    decode('cafebabe', 'hex'),
    'aes-256-gcm.v1',
    'v2',
    now() + interval '1 hour',
    true,
    ARRAY['https://www.googleapis.com/auth/youtube.readonly','https://www.googleapis.com/auth/yt-analytics.readonly']
  ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION '073 failed: same-channel reconnect was rejected';
  END IF;
END;
$runtime_reconnect$;

RESET ROLE;

DO $reconnected_state$
DECLARE
  actual_state text;
  actual_error text;
  credential_count integer;
BEGIN
  SELECT state, error_class INTO actual_state, actual_error
    FROM growth.platform_connections
   WHERE id = 'c0000000-0000-4000-8000-000000000733';
  SELECT count(*) INTO credential_count
    FROM growth.provider_credentials
   WHERE platform_connection_id = 'c0000000-0000-4000-8000-000000000733'
     AND provider = 'youtube'
     AND key_version = 'v2';

  IF actual_state <> 'connected' OR actual_error IS NOT NULL OR credential_count <> 1 THEN
    RAISE EXCEPTION '073 failed: reconnect did not restore the credential atomically';
  END IF;
END;
$reconnected_state$;

ROLLBACK;

\echo 'PASS: YouTube connection revocation removes OAuth material and preserves safe same-channel reconnect'
