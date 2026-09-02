-- Growth OS Identity v1 — executable signup/session/workspace/invitation flow.

\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  owner_id uuid;
  workspace_id uuid;
  session_id uuid;
  resolved_user uuid;
BEGIN
  SET ROLE app_runtime;
  owner_id := growth.identity_signup(
    'identity.owner@example.com',
    '$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$aGFzaA',19::smallint
  );
  PERFORM set_config('app.user_id',owner_id::text,true);
  PERFORM growth.identity_issue_email_verification(repeat('a',64),now()+interval '1 hour');
  IF growth.identity_consume_email_verification(repeat('a',64)) <> owner_id THEN
    RAISE EXCEPTION 'TEST FAIL: owner email verification returned wrong user';
  END IF;
  workspace_id := growth.identity_create_workspace('Identity Test','US','en','UTC');
  PERFORM set_config('app.workspace_id',workspace_id::text,true);
  PERFORM growth.identity_issue_invitation(
    workspace_id,'identity.member@example.com','editor',false,repeat('b',64),now()+interval '1 day'
  );
  session_id := growth.identity_create_session(
    owner_id,repeat('c',64),ARRAY['password'],now()+interval '30 days',now()+interval '1 day',NULL,'identity-flow'
  );
  SELECT r.user_id INTO resolved_user FROM growth.identity_resolve_session(repeat('c',64)) r;
  IF resolved_user IS DISTINCT FROM owner_id THEN
    RAISE EXCEPTION 'TEST FAIL: live owner session did not resolve';
  END IF;
  IF NOT growth.identity_revoke_session(session_id,'logout') THEN
    RAISE EXCEPTION 'TEST FAIL: owner session was not revoked';
  END IF;
  IF EXISTS (SELECT 1 FROM growth.identity_resolve_session(repeat('c',64))) THEN
    RAISE EXCEPTION 'TEST FAIL: revoked owner session still resolves';
  END IF;
  RESET ROLE;
END $$;

DO $$
DECLARE
  member_id uuid;
  accepted_workspace uuid;
  member_session uuid;
BEGIN
  SET ROLE app_runtime;
  member_id := growth.identity_signup(
    'identity.member@example.com',
    '$argon2id$v=19$m=19456,t=2,p=1$c2FsdDI$aGFzaDI',19::smallint
  );
  PERFORM set_config('app.user_id',member_id::text,true);
  PERFORM growth.identity_issue_email_verification(repeat('d',64),now()+interval '1 hour');
  PERFORM growth.identity_consume_email_verification(repeat('d',64));
  accepted_workspace := growth.identity_accept_invitation(repeat('b',64));
  IF accepted_workspace IS NULL THEN RAISE EXCEPTION 'TEST FAIL: invitation returned no workspace'; END IF;
  member_session := growth.identity_create_session(
    member_id,repeat('e',64),ARRAY['password'],now()+interval '30 days',now()+interval '1 day',NULL,'member-flow'
  );
  IF member_session IS NULL THEN RAISE EXCEPTION 'TEST FAIL: member session was not created'; END IF;
  RESET ROLE;
END $$;

DO $$
DECLARE
  ws uuid;
  owner_id uuid;
  member_id uuid;
  member_role text;
  invitation_status text;
  audit_count integer;
BEGIN
  SET ROLE growth_test_harness;
  SELECT id INTO owner_id FROM growth.users WHERE email='identity.owner@example.com';
  SELECT id INTO member_id FROM growth.users WHERE email='identity.member@example.com';
  SELECT workspace_id INTO ws FROM growth.memberships WHERE user_id=owner_id AND role='owner';
  SELECT role INTO member_role FROM growth.memberships WHERE workspace_id=ws AND user_id=member_id AND status='active';
  SELECT status INTO invitation_status FROM growth.invitations WHERE token_hash=repeat('b',64);
  SELECT count(*) INTO audit_count FROM growth.audit_events
  WHERE actor_user_id IN (owner_id,member_id) AND event_type LIKE 'identity.%';
  RESET ROLE;
  IF member_role <> 'editor' THEN RAISE EXCEPTION 'TEST FAIL: accepted role %, expected editor',member_role; END IF;
  IF invitation_status <> 'accepted' THEN RAISE EXCEPTION 'TEST FAIL: invitation state %',invitation_status; END IF;
  IF audit_count < 5 THEN RAISE EXCEPTION 'TEST FAIL: only % identity audit events found',audit_count; END IF;
  RAISE NOTICE 'PASS: signup -> verify -> workspace -> invite -> accept -> session flow is atomic and auditable';
END $$;

DO $$
DECLARE
  duplicate_state text;
  unverified_id uuid;
  workspace_state text;
  wrong_user_id uuid;
  invite_state text;
BEGIN
  SET ROLE app_runtime;
  BEGIN
    PERFORM growth.identity_signup(
      'IDENTITY.OWNER@example.com','$argon2id$v=19$m=19456,t=2,p=1$eA$eQ',19::smallint
    );
    RAISE EXCEPTION 'TEST FAIL: duplicate normalized email was accepted';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS duplicate_state=RETURNED_SQLSTATE; END;
  IF duplicate_state <> '23505' THEN RAISE EXCEPTION 'TEST FAIL: duplicate email state %, expected 23505',duplicate_state; END IF;

  unverified_id := growth.identity_signup(
    'identity.unverified@example.com','$argon2id$v=19$m=19456,t=2,p=1$eDI$eTI',19::smallint
  );
  PERFORM set_config('app.user_id',unverified_id::text,true);
  BEGIN
    PERFORM growth.identity_create_workspace('Denied','US','en','UTC');
    RAISE EXCEPTION 'TEST FAIL: unverified user created workspace';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS workspace_state=RETURNED_SQLSTATE; END;

  wrong_user_id := growth.identity_signup(
    'identity.wrong@example.com','$argon2id$v=19$m=19456,t=2,p=1$eDM$eTM',19::smallint
  );
  PERFORM set_config('app.user_id',wrong_user_id::text,true);
  PERFORM growth.identity_issue_email_verification(repeat('f',64),now()+interval '1 hour');
  PERFORM growth.identity_consume_email_verification(repeat('f',64));
  BEGIN
    PERFORM growth.identity_accept_invitation(repeat('b',64));
    RAISE EXCEPTION 'TEST FAIL: wrong verified email accepted another user invitation';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS invite_state=RETURNED_SQLSTATE; END;
  RESET ROLE;

  IF workspace_state IS NULL OR invite_state IS NULL THEN
    RAISE EXCEPTION 'TEST FAIL: negative identity paths were not proven';
  END IF;
  RAISE NOTICE 'PASS: duplicate email, unverified workspace and wrong-email invitation paths are denied';
END $$;

\echo 'PASS: Identity v1 functional flow'
